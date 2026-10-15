#!/usr/bin/env ruby
# Verify the exact uploaded t. build before adding it to internal TestFlight.
require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

class AppStoreConnect
  def initialize
    @key=OpenSSL::PKey.read(File.read(ENV.fetch('ASC_KEY_PATH')))
  end
  def request(method,path,params: {},body: nil)
    uri=URI("https://api.appstoreconnect.apple.com/v1#{path}")
    uri.query=URI.encode_www_form(params) unless params.empty?
    now=Time.now.to_i
    header={alg:'ES256',kid:ENV.fetch('ASC_KEY_ID'),typ:'JWT'}
    claims={iss:ENV.fetch('ASC_ISSUER_ID'),iat:now,exp:now+1200,aud:'appstoreconnect-v1'}
    unsigned=[header,claims].map{|item|Base64.urlsafe_encode64(JSON.generate(item),padding:false)}.join('.')
    signature=OpenSSL::ASN1.decode(@key.sign('SHA256',unsigned)).value.map{|n|[n.value.to_s(16).rjust(64,'0')].pack('H*')}.join
    token=unsigned+'.'+Base64.urlsafe_encode64(signature,padding:false)
    req={get:Net::HTTP::Get,post:Net::HTTP::Post}.fetch(method).new(uri)
    req['Authorization']='Bearer '+token
    req['Accept']='application/json'
    req['Content-Type']='application/json'
    req.body=JSON.generate(body) unless body.nil?
    retry_delays=[5,10,20,30]
    attempt=0
    begin
      response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:20,read_timeout:45){|http|http.request(req)}
    rescue SocketError, Timeout::Error, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
      # Reads are safe to repeat; an interrupted write may already have succeeded.
      raise unless method==:get && attempt<retry_delays.length
      delay=retry_delays[attempt]
      attempt+=1
      warn "Temporary network failure during a read-only Apple API check; retrying (#{attempt}/#{retry_delays.length})"
      sleep delay
      retry
    end
    parsed=response.body.to_s.empty? ? {} : JSON.parse(response.body)
    unless response.code.to_i.between?(200,299)
      raise "App Store Connect #{response.code}: #{Array(parsed['errors']).map{|e|[e['code'],e['detail']].compact.join(': ')}.join('; ')}"
    end
    parsed
  end
end

client=AppStoreConnect.new
app_id=ENV.fetch('ASC_APP_ID')
app=client.request(:get,"/apps/#{app_id}")['data']
raise 'Refusing to distribute a different app' unless app.dig('attributes','bundleId')==ENV.fetch('BUNDLE_ID')
version=JSON.parse(File.read('versions.json')).fetch('app')
build_number=ENV.fetch('BUILD_NUMBER')
deadline=Time.now+2700
build=nil
loop do
  response=client.request(:get,'/builds',params:{'filter[app]'=>app_id,'filter[version]'=>build_number,'include'=>'preReleaseVersion'})
  matches=response.fetch('data').select do |candidate|
    train_id=candidate.dig('relationships','preReleaseVersion','data','id')
    train=Array(response['included']).find{|r|r['type']=='preReleaseVersions' && r['id']==train_id}
    train && train.dig('attributes','version')==version && train.dig('attributes','platform')=='IOS'
  end
  raise 'Multiple builds match this upload' if matches.length>1
  build=matches.first
  state=build&.dig('attributes','processingState')
  raise "Apple rejected this build: #{state}" if %w[INVALID FAILED].include?(state)
  break if state=='VALID'
  raise 'Build processing has not completed; inspect App Store Connect before another upload' if Time.now>=deadline
  puts "Waiting for t. #{version} (#{build_number}) processing: #{state || 'not yet listed'}"
  sleep 30
end
raise 'The build has expired' if build.dig('attributes','expired')
raise 'This build is restricted to internal TestFlight' unless build.dig('attributes','buildAudienceType')=='APP_STORE_ELIGIBLE'
groups=client.request(:get,"/apps/#{app_id}/betaGroups")['data']
group=groups.find{|r|r.dig('attributes','name')=='t. Internal' && r.dig('attributes','isInternalGroup')}
unless group
  group=client.request(:post,'/betaGroups',body:{data:{type:'betaGroups',attributes:{name:'t. Internal',isInternalGroup:true,hasAccessToAllBuilds:false},relationships:{app:{data:{type:'apps',id:app_id}}}}})['data']
end
existing=client.request(:get,"/betaGroups/#{group['id']}/builds")['data']
unless existing.any?{|r|r['id']==build['id']}
  client.request(:post,"/betaGroups/#{group['id']}/relationships/builds",body:{data:[{type:'builds',id:build['id']}]})
end
verified=client.request(:get,"/betaGroups/#{group['id']}/builds")['data']
raise 'TestFlight group attachment was not persisted' unless verified.any?{|r|r['id']==build['id']}
detail=client.request(:get,"/builds/#{build['id']}/buildBetaDetail")['data']['attributes']
summary={app:'t.',marketingVersion:version,buildNumber:build_number,processingState:build.dig('attributes','processingState'),buildAudience:build.dig('attributes','buildAudienceType'),internalBuildState:detail['internalBuildState'],externalBuildState:detail['externalBuildState'],internalGroup:group.dig('attributes','name')}
File.write('build/artifacts/testflight-status.json',JSON.pretty_generate(summary)+"\n")
puts JSON.pretty_generate(summary)
