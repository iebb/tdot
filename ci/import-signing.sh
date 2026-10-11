#!/bin/bash
set -euo pipefail
: "${CERTIFICATE_P12:?missing IOS_SIGNING_CERTIFICATE_P12}"
: "${CERTIFICATE_PASSWORD:?missing IOS_SIGNING_CERTIFICATE_PASSWORD}"
: "${PROFILES_TAR_GZ:?missing IOS_PROVISIONING_PROFILES_TAR_GZ}"
: "${ASC_PRIVATE_KEY:?missing APP_STORE_CONNECT_PRIVATE_KEY}"
: "${ASC_KEY_ID:?missing APP_STORE_CONNECT_KEY_ID}"
: "${ASC_ISSUER_ID:?missing APP_STORE_CONNECT_ISSUER_ID}"
: "${ASC_APP_ID:?missing ASC_APP_ID secret}"
material="$RUNNER_TEMP/tdot-signing"
keys="$RUNNER_TEMP/tdot-private-keys"
mkdir -p "$material" "$keys" build-input/codesigning/profiles build-input/codesigning/certs
chmod 700 "$material" "$keys"
printf '%s' "$CERTIFICATE_P12" | base64 --decode > "$material/signing.p12"
printf '%s' "$PROFILES_TAR_GZ" | base64 --decode > "$material/profiles.tar.gz"
tar -xzf "$material/profiles.tar.gz" -C build-input/codesigning/profiles
python3 - <<'PYMASK'
import plistlib,subprocess
from pathlib import Path
for path in Path('build-input/codesigning/profiles').glob('*.mobileprovision'):
    profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(path)],stderr=subprocess.DEVNULL))
    values=[profile.get('UUID'),profile.get('Name'),*profile.get('TeamIdentifier',[])]
    for value in values:
        if value:
            print('::add-mask::'+value)
PYMASK
keychain="$material/signing.keychain-db"
password="$(openssl rand -hex 24)"
echo "::add-mask::$password"
security create-keychain -p "$password" "$keychain"
printf 'SIGNING_KEYCHAIN=%s\n' "$keychain" >> "$GITHUB_ENV"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$material/signing.p12" -k "$keychain" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security import build-system/AppleWWDRCAG3.cer -k "$keychain" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security find-identity -v -p codesigning "$keychain" >/dev/null
printf '%s\n' "$ASC_PRIVATE_KEY" > "$keys/AuthKey_${ASC_KEY_ID}.p8"
chmod 600 "$keys/AuthKey_${ASC_KEY_ID}.p8"
printf 'ASC_KEY_PATH=%s\n' "$keys/AuthKey_${ASC_KEY_ID}.p8" >> "$GITHUB_ENV"
