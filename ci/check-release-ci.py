"""Do not hide a failed/missing signed release behind an older live beta."""
import importlib.util
import json
import os
from pathlib import Path

spec = importlib.util.spec_from_file_location("sync", Path(__file__).with_name("sync-upstream.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


def verify(run, state, offset):
    if run["status"] != "completed":
        print("A signed release is in progress; existing TestFlight distribution is preserved.")
        return
    expected = str(run["run_number"] + offset)
    if not state or str(state.get("build")) != expected:
        raise RuntimeError("The current source's exact signed release is missing; inspect its CI run before another upload")
    # A post-upload monitor can fail although Apple has the exact valid build.
    if state.get("processing") != "VALID" or state.get("audience") != "APP_STORE_ELIGIBLE":
        raise RuntimeError("The exact signed release is not eligible")
    print("Exact signed CI build reconciled with Apple; any pending beta review is preserved.")


if __name__ == "__main__":
    pin = json.loads(Path("versions.json").read_text())["nagram_revision"]
    if sync.api(sync.UPSTREAM, "/commits/HEAD")["sha"] != pin:
        print("A new upstream snapshot is being reconciled by the sync job.")
        raise SystemExit(0)
    run = next(sync.source_builds(pin), None)
    if run is None:
        raise RuntimeError("This source has no signed CI run; release dispatch reconciliation is required")
    path = Path("build/artifacts/testflight-publication.json")
    state = json.loads(path.read_text()) if path.exists() else None
    offset = os.environ["BUILD_NUMBER_OFFSET"]
    if not offset.isdigit():
        raise RuntimeError("Missing or invalid private build-number offset")
    verify(run, state, int(offset))
