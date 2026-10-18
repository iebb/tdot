require 'tmpdir'
require 'minitest/autorun'
require_relative '../testflight'

class PublicationClient
  attr_reader :writes
  def initialize(review: 'WAITING_FOR_REVIEW', processing: 'VALID')
    @review=review
    @processing=processing
    @writes=[]
  end
  def request(method,path,params: {},body: nil)
    @writes << path unless method==:get
    groups=[{type:'betaGroups',id:'internal',attributes:{name:'t. Internal',isInternalGroup:true}},
            {type:'betaGroups',id:'external',attributes:{name:'t. External',isInternalGroup:false,publicLinkEnabled:true,publicLink:'https://testflight.apple.com/join/Example1'}}]
    data=case path
    when '/apps/test-app' then {attributes:{bundleId:'test.bundle'}}
    when '/builds' then return JSON.parse(JSON.generate({data:[{id:'build',attributes:{version:'111',processingState:@processing,buildAudienceType:'APP_STORE_ELIGIBLE',expired:false},relationships:{preReleaseVersion:{data:{id:'train'}}}}],included:[{type:'preReleaseVersions',id:'train',attributes:{version:'1.0.0',platform:'IOS'}}]}))
    when '/apps/test-app/betaGroups', '/builds/build/betaGroups' then groups
    when '/builds/build/betaBuildLocalizations' then [{attributes:{locale:'en-CA',whatsNew:'Existing notes'}}]
    when '/builds/build/buildBetaDetail' then {id:'detail',attributes:{autoNotifyEnabled:true,internalBuildState:'IN_BETA_TESTING',externalBuildState:@review=='APPROVED' ? 'IN_BETA_TESTING' : 'WAITING_FOR_BETA_REVIEW'}}
    when '/betaAppReviewSubmissions' then [{attributes:{betaReviewState:@review}}]
    when '/apps/test-app/appStoreVersions' then [{id:'store',attributes:{appStoreState:'WAITING_FOR_REVIEW'}}]
    else raise "Unexpected endpoint #{path}"
    end
    JSON.parse(JSON.generate({data:data}))
  end
end

class PublicationTests < Minitest::Test
  def run_publication(client)
    script=File.expand_path('../testflight-publication.rb',__dir__)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('versions.json',JSON.generate({app:'1.0.0',nagram_revision:'a'*40}))
        old=ENV.to_h
        begin
          ENV['ASC_APP_ID']='test-app'
          ENV['BUNDLE_ID']='test.bundle'
          ENV.delete('BUILD_NUMBER')
          AppStoreConnect.stub(:new,client) { capture_io { load script } }
          yield JSON.parse(File.read('build/artifacts/testflight-publication.json'))
        ensure
          ENV.replace(old)
        end
      end
    end
  end
  def test_pending_review_is_preserved_and_no_store_submission_is_changed
    client=PublicationClient.new
    run_publication(client) { |state| refute state['publicationComplete'] }
    assert_empty client.writes
  end
  def test_approved_both_audiences_is_complete
    client=PublicationClient.new(review:'APPROVED')
    run_publication(client) { |state| assert state['publicationComplete']; assert state['bothGroupsAttached'] }
    assert_empty client.writes
  end
  def test_rejected_review_fails_without_resubmission
    client=PublicationClient.new(review:'REJECTED')
    assert_raises(RuntimeError) { run_publication(client) {} }
    assert_empty client.writes
  end
end
