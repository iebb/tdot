import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("release_ci", Path(__file__).parents[1] / "check-release-ci.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecks(unittest.TestCase):
    def test_post_upload_monitor_failure_does_not_replace_verified_build(self):
        release.verify({"status": "completed", "conclusion": "failure", "run_number": 12},
                       {"build": "112", "processing": "VALID", "audience": "APP_STORE_ELIGIBLE"}, 100)

    def test_older_live_beta_does_not_hide_failed_current_release(self):
        with self.assertRaises(RuntimeError):
            release.verify({"status": "completed", "conclusion": "failure", "run_number": 12},
                           {"build": "110", "processing": "VALID", "audience": "APP_STORE_ELIGIBLE"}, 100)

    def test_pending_build_preserves_existing_distribution(self):
        release.verify({"status": "in_progress", "run_number": 12}, None, 100)

    def test_internal_only_build_is_not_accepted(self):
        with self.assertRaises(RuntimeError):
            release.verify({"status": "completed", "run_number": 12},
                           {"build": "112", "processing": "VALID", "audience": "INTERNAL_ONLY"}, 100)
