#!/usr/bin/env python3
"""Reject an IPA with the wrong identity, signer, profiles, or missing extensions."""
import datetime,json,os,plistlib,subprocess,sys,tempfile
from pathlib import Path
TEAM=os.environ['TEAM_ID']
BUNDLE=os.environ['BUNDLE_ID']
APP_GROUP=os.environ['APP_GROUP_ID']
EXTENSIONS={BUNDLE+suffix for suffix in ('.Share','.NotificationContent','.NotificationService','.SiriIntents','.Widget','.BroadcastUpload')}

def verify_bundle(app,expected):
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']==expected, f'Wrong bundle ID: {app.name}'
    profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app/'embedded.mobileprovision')],stderr=subprocess.DEVNULL))
    entitlements=profile['Entitlements']
    assert profile['TeamIdentifier']==[TEAM], 'Wrong signing team'
    assert entitlements['application-identifier']==TEAM+'.'+expected, 'Wrong provisioning identity'
    assert not entitlements.get('get-task-allow',False), 'Development profile cannot ship'
    assert 'ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices',False), 'App Store profile required'
    assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
    assert APP_GROUP in entitlements.get('com.apple.security.application-groups',[]), 'Missing shared App Group'
    assert info['CFBundleVersion']==os.environ['BUILD_NUMBER'], 'Wrong build number'
    assert info['CFBundleShortVersionString']==json.loads(Path('versions.json').read_text())['app'], 'Wrong marketing version'
    subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
    with tempfile.TemporaryDirectory() as certificate_folder:
        prefix=str(Path(certificate_folder)/'signer')
        subprocess.run(['codesign','-d','--extract-certificates='+prefix,str(app)],check=True,stderr=subprocess.DEVNULL)
        assert Path(prefix+'0').read_bytes() in profile['DeveloperCertificates'], 'Signing certificate is not authorized by the profile'
    signed=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
    assert signed['application-identifier']==TEAM+'.'+expected, 'Wrong signed application identity'
    assert signed.get('com.apple.security.application-groups')==[APP_GROUP], 'Wrong signed App Group'
    if expected==BUNDLE:
        assert info['CFBundleDisplayName']=='t.' and info['CFBundleName']=='t.', 'Wrong display name'
        assert entitlements['aps-environment']=='production', 'Production APNs required'
        assert signed.get('aps-environment')=='production', 'Wrong signed APNs environment'
    return info

with tempfile.TemporaryDirectory() as folder:
    subprocess.run(['ditto','-x','-k',sys.argv[1],folder],check=True)
    apps=list((Path(folder)/'Payload').glob('*.app'))
    assert len(apps)==1, 'Expected one application'
    verify_bundle(apps[0],BUNDLE)
    extensions=list((apps[0]/'PlugIns').glob('*.appex'))
    actual={plistlib.loads((extension/'Info.plist').read_bytes())['CFBundleIdentifier'] for extension in extensions}
    assert actual==EXTENSIONS, 'Missing or unexpected extensions'
    for extension in extensions:
        verify_bundle(extension,plistlib.loads((extension/'Info.plist').read_bytes())['CFBundleIdentifier'])
    subprocess.run(['codesign','--verify','--deep','--strict',str(apps[0])],check=True)
print('Verified t.: Kitta App Store signing, bundle, version, production APNs, shared group, and all six extensions')
