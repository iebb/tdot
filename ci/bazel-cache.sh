#!/bin/bash
set -euo pipefail
: "${CI_CACHE_KEY:?missing CI_CACHE_KEY secret}"
: "${RUNNER_TEMP:?missing runner temporary directory}"
plain="${TDOT_BAZEL_CACHE_DIR:-$HOME/telegram-bazel-cache}"
sealed="${TDOT_ENCRYPTED_CACHE_DIR:-$RUNNER_TEMP/tdot-encrypted-cache}"
archive="$RUNNER_TEMP/tdot-bazel-cache.tar.gz"
trap 'python3 -c "import pathlib; pathlib.Path(\"$archive\").unlink(missing_ok=True)"' EXIT
case "${1:-}" in
  save)
    if [[ ! -d "$plain" ]]; then exit 0; fi
    mkdir -p "$sealed"
    tar -czf "$archive" -C "$plain" .
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 -pass env:CI_CACHE_KEY -in "$archive" -out "$sealed/cache.enc"
    python3 - "$sealed" <<'PY'
import hashlib,hmac,os,sys
from pathlib import Path
folder=Path(sys.argv[1]);key=hashlib.sha256((os.environ['CI_CACHE_KEY']+':tdot-cache-authentication').encode()).digest()
mac=hmac.new(key,digestmod=hashlib.sha256)
with (folder/'cache.enc').open('rb') as f:
    for chunk in iter(lambda:f.read(1024*1024),b''):mac.update(chunk)
(folder/'cache.hmac').write_text(mac.hexdigest())
PY
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo 'ready=true' >> "$GITHUB_OUTPUT"; fi
    ;;
  restore)
    python3 - "$sealed" <<'PY'
import hashlib,hmac,os,sys
from pathlib import Path
folder=Path(sys.argv[1]);key=hashlib.sha256((os.environ['CI_CACHE_KEY']+':tdot-cache-authentication').encode()).digest()
mac=hmac.new(key,digestmod=hashlib.sha256)
with (folder/'cache.enc').open('rb') as f:
    for chunk in iter(lambda:f.read(1024*1024),b''):mac.update(chunk)
if not hmac.compare_digest(mac.hexdigest(),(folder/'cache.hmac').read_text().strip()):
    raise SystemExit('Compiled cache authentication failed')
PY
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -pass env:CI_CACHE_KEY -in "$sealed/cache.enc" -out "$archive"
    mkdir -p "$plain"
    tar -xzf "$archive" -C "$plain"
    ;;
  *) echo 'Usage: bazel-cache.sh restore|save' >&2; exit 2 ;;
esac
