#!/usr/bin/env ruby
# Resume the exact eligible release; never upload, invite testers or publish privacy.
require_relative 'testflight'
require 'fileutils'
require 'time'

c=AppStoreConnect.new
app=ENV.fetch('ASC_APP_ID')
raise 'Different app identity' unless c.request(:get,"/apps/#{app}")['data'].dig('attributes','bundleId')==ENV.fetch('BUNDLE_ID')
version=JSON.parse(File.read('versions.json')).fetch('app')
params={'filter[app]'=>app,'include'=>'preReleaseVersion','sort'=>'-uploadedDate','limit'=>100}
params['filter[version]']=ENV['BUILD_NUMBER'] if ENV['BUILD_NUMBER'] && !ENV['BUILD_NUMBER'].empty?
response=c.request(:get,'/builds',params:params)
matches=response.fetch('data').select do |b|
  train=Array(response['included']).find{|r|r['id']==b.dig('relationships','preReleaseVersion','data','id') && r['type']=='preReleaseVersions'}
  train && train.dig('attributes','version')==version && train.dig('attributes','platform')=='IOS'
end
raise 'Release train has no build' if matches.empty?
raise 'Ambiguous exact build' if params['filter[version]'] && matches.length!=1
b=matches.first
attributes=b.fetch('attributes')
raise 'Latest release build failed processing' if %w[INVALID FAILED].include?(attributes['processingState'])
if attributes['processingState']!='VALID'
  puts 'Latest exact release is still processing; preserving upload and existing distribution.'
  exit 0
end
raise 'Build is expired or internal-only' if attributes['expired'] || attributes['buildAudienceType']!='APP_STORE_ELIGIBLE'
groups=c.request(:get,"/apps/#{app}/betaGroups",params:{'limit'=>200})['data']
selected=['t. Internal','t. External'].map do |name|
  found=groups.select{|g|g.dig('attributes','name')==name}
  raise 'Expected existing unique TestFlight group' unless found.length==1
  found.first
end
raise 'Incorrect TestFlight audience types' unless selected[0].dig('attributes','isInternalGroup') && !selected[1].dig('attributes','isInternalGroup')
external_group=selected[1]
# Keep the existing public enrollment open up to Apple's external-tester cap.
# This changes capacity only; it neither invites testers nor bypasses beta review.
if external_group.dig('attributes','publicLinkEnabled') && external_group.dig('attributes','publicLinkLimitEnabled') && external_group.dig('attributes','publicLinkLimit').to_i<10_000
  c.request(:patch,"/betaGroups/#{external_group['id']}",body:{data:{type:'betaGroups',id:external_group['id'],attributes:{publicLinkLimit:10_000}}})
  selected[1]=c.request(:get,"/betaGroups/#{external_group['id']}")['data']
  raise 'Public enrollment capacity did not persist' unless selected[1].dig('attributes','publicLinkLimit')==10_000
end
selected.each do |g|
  attached=c.request(:get,"/betaGroups/#{g['id']}/builds",params:{'limit'=>200})['data']
  unless attached.any?{|r|r['id']==b['id']}
    c.request(:post,"/betaGroups/#{g['id']}/relationships/builds",body:{data:[{type:'builds',id:b['id']}]})
  end
end
locales=c.request(:get,"/builds/#{b['id']}/betaBuildLocalizations")['data']
unless locales.any?{|l|l.dig('attributes','locale')=='en-CA' && !l.dig('attributes','whatsNew').to_s.empty?}
  notes='Updated to Nagram '+JSON.parse(File.read('versions.json')).fetch('nagram_revision')[0,12]+'. Please test chats, search, media and the eight-category t. extra settings. The existing Ayu privacy controls, local message history and preferences are preserved. AyuSync remains deferred.'
  locale=locales.find{|l|l.dig('attributes','locale')=='en-CA'}
  if locale
    c.request(:patch,"/betaBuildLocalizations/#{locale['id']}",body:{data:{type:'betaBuildLocalizations',id:locale['id'],attributes:{whatsNew:notes}}})
  else
    c.request(:post,'/betaBuildLocalizations',body:{data:{type:'betaBuildLocalizations',attributes:{locale:'en-CA',whatsNew:notes},relationships:{build:{data:{type:'builds',id:b['id']}}}}})
  end
end
detail=c.request(:get,"/builds/#{b['id']}/buildBetaDetail")['data']
unless detail.dig('attributes','autoNotifyEnabled')
  c.request(:patch,"/buildBetaDetails/#{detail['id']}",body:{data:{type:'buildBetaDetails',id:detail['id'],attributes:{autoNotifyEnabled:true}}})
end
review=c.request(:get,'/betaAppReviewSubmissions',params:{'filter[build]'=>b['id']})['data'].first
raise 'Apple rejected beta review; inspect the exact review issue' if review && %w[REJECTED BETA_REJECTED].include?(review.dig('attributes','betaReviewState'))
unless review || detail.dig('attributes','externalBuildState')=='IN_BETA_TESTING'
  review=c.request(:post,'/betaAppReviewSubmissions',body:{data:{type:'betaAppReviewSubmissions',relationships:{build:{data:{type:'builds',id:b['id']}}}}})['data']
end
detail=c.request(:get,"/builds/#{b['id']}/buildBetaDetail")['data']['attributes']
raise 'Audience attachment did not persist' unless selected.all? do |g|
  c.request(:get,"/betaGroups/#{g['id']}/builds",params:{'limit'=>200})['data'].any?{|r|r['id']==b['id']}
end
external=selected[1]['attributes']
raise 'Public TestFlight link is disabled' unless external['publicLinkEnabled']
link=external.fetch('publicLink')
raise 'Unexpected public TestFlight URL' unless link.match?(%r{\Ahttps://testflight\.apple\.com/join/[A-Za-z0-9]+\z})
store=c.request(:get,"/apps/#{app}/appStoreVersions",params:{'filter[platform]'=>'IOS','filter[versionString]'=>version})['data']
raise 'Ambiguous App Store version' if store.length>1
if store.first && store.first.dig('attributes','appStoreState')=='PREPARE_FOR_SUBMISSION'
  id=store.first['id']
  current=c.request(:get,"/appStoreVersions/#{id}/build")['data']
  unless current && current['id']==b['id']
    # This relationship edit does not submit the app or any privacy declaration.
    c.request(:patch,"/appStoreVersions/#{id}/relationships/build",body:{data:{type:'builds',id:b['id']}})
  end
  raise 'Store build attachment did not persist' unless c.request(:get,"/appStoreVersions/#{id}/build")['data']['id']==b['id']
end
summary={app:'t.',version:version,build:attributes['version'],processing:attributes['processingState'],audience:attributes['buildAudienceType'],internal:detail['internalBuildState'],external:detail['externalBuildState'],betaReviewState:review&.dig('attributes','betaReviewState'),bothGroupsAttached:true,publicLink:link,autoPublishAfterApproval:detail['autoNotifyEnabled'],verifiedAt:Time.now.utc.iso8601}
summary[:audiencesActive]=summary[:internal]=='IN_BETA_TESTING' && summary[:external]=='IN_BETA_TESTING' && summary[:betaReviewState]=='APPROVED'
summary[:publicationComplete]=false # The rendered public-page check completes verification.
FileUtils.mkdir_p('build/artifacts')
File.write('build/artifacts/testflight-publication.json',JSON.pretty_generate(summary)+"\n")
puts JSON.pretty_generate(summary)
