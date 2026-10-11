#!/usr/bin/env python3
"""Require a current Nagram source pin before building or uploading a release."""
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

revision = json.loads(Path("versions.json").read_text()).get("nagram_revision")
if not isinstance(revision, str) or len(revision) != 40:
    sys.exit("Record the synced Nagram revision in versions.json before building.")

headers = {"Accept": "application/vnd.github+json", "User-Agent": "tdot-upstream-check"}
if os.environ.get("GH_TOKEN"):
    headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
request = urllib.request.Request(
    "https://api.github.com/repos/NextAlone/Nagram-iOS/commits/HEAD", headers=headers
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        latest = json.load(response)["sha"]
except (OSError, ValueError, KeyError, urllib.error.HTTPError):
    sys.exit("Could not verify the current Nagram revision. Retry before releasing.")

if latest != revision:
    sys.exit("Nagram has newer commits. Sync its app changes and preserve the Ayu overlay before releasing.")
print("Nagram upstream is current at " + revision[:12] + ".")
