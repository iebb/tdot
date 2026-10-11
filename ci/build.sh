#!/bin/bash
set -euo pipefail
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi
: "${APP_HASH:?Set the t. APP_HASH secret}"
: "${BUILD_NUMBER:?Set a unique build number}"
cat > local.bazelrc <<'RC'
# MARK: NEXTGRAM — upstream Xcode 27 native compiler compatibility.
build --features=no_include_scanning
build --host_features=no_include_scanning
build --copt=-Wno-error
build --cxxopt=-Wno-error
build --objccopt=-Wno-error
build --@build_bazel_rules_swift//swift:copt=-no-warnings-as-errors
RC
mkdir -p build-input build/artifacts
python3 - <<'PY'
import json,os
from pathlib import Path
configuration=json.loads(Path('build-system/appstore-configuration.json').read_text())
if os.environ.get('ASC_APP_ID'):
    configuration['appstore_id']=os.environ['ASC_APP_ID']
Path('build-input/tdot.json').write_text(json.dumps(configuration))
PY
if [[ "$DISTRIBUTION" == 'testflight' ]]; then
  python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir "$HOME/telegram-bazel-cache" build \
    --configurationPath build-input/tdot.json --codesigningInformationPath build-input/codesigning \
    --buildNumber "$BUILD_NUMBER" --configuration release_arm64
else
  cat >> local.bazelrc <<'SIMULATOR'
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
SIMULATOR
  python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir "$HOME/telegram-bazel-cache" build \
    --configurationPath build-input/tdot.json --xcodeManagedCodesigning \
    --buildNumber "$BUILD_NUMBER" --configuration release_sim_arm64
fi
cp bazel-bin/Telegram/Telegram.ipa build/artifacts/tdot.ipa
for symbols in bazel-bin/Telegram/*.dSYM; do
  if [[ -d "$symbols" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$symbols" "build/artifacts/$(basename "$symbols").zip"
  fi
done
