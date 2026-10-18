import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sync", Path(__file__).parents[1] / "sync-upstream.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def test_protected_paths(self):
        for path in (".env", ".github/workflows/build.yml", "ci/build.sh", "Nagram/../../.env", "Telegram/key.p8", "/Nagram/file.swift"):
            self.assertFalse(sync.allowed(path))
        self.assertTrue(sync.allowed("submodules/TelegramUI/Chat.swift"))

    def test_secrets_and_markers_rejected(self):
        for data in (b'APP_ID = 12345678', b'APP_HASH = "' + b'a' * 32 + b'"',
                     b'sk-or-v1-example', b'<<<<<<< ours\nsecret\n', b'-----BEGIN PRIVATE KEY-----'):
            with self.assertRaises(RuntimeError):
                sync.scan(data)

    def test_clean_merge_keeps_both_sides_without_model(self):
        base = b"a\nb\nc\nd\ne\n"
        ours = b"A\nb\nc\nd\ne\n"
        theirs = b"a\nb\nc\nd\nE\n"
        reviewer = sync.Reviewer()
        self.assertEqual(sync.merge("Nagram/test.swift", base, ours, theirs, reviewer), b"A\nb\nc\nd\nE\n")
        self.assertEqual(reviewer.calls, 0)

    def test_model_resolves_only_conflict(self):
        reviewer = sync.Reviewer()
        with patch.object(reviewer, "ask", return_value={"decision": "merge", "content": "overlay + upstream\n"}):
            merged = sync.merge("Nagram/test.swift", b"start\na\nend\n", b"start\nb\nend\n", b"start\nc\nend\n", reviewer)
        self.assertEqual(merged, b"start\noverlay + upstream\nend\n")

    def test_settings_reorganization_gets_complete_file_context(self):
        reviewer = sync.Reviewer()
        with patch.object(reviewer, "ask", return_value={"decision": "merge", "content": "", "edits": [{"before": "ours\n", "after": "resolved\n"}]}) as ask:
            merged = sync.merge("Nagram/SettingsUI/Example.swift", b"base\n", b"ours\n", b"upstream\n", reviewer)
        self.assertEqual(merged, b"resolved\n")
        self.assertTrue(ask.call_args.args[0].startswith("Resolve complete file"))
        self.assertEqual(ask.call_args.args[1]["ours"], "ours\n")
        self.assertIn("categoryHub", ask.call_args.args[1])

    def test_ambiguous_full_file_edit_fails_closed(self):
        reviewer = sync.Reviewer()
        with patch.object(reviewer, "ask", return_value={"decision": "merge", "edits": [{"before": "ours", "after": "resolved"}]}), self.assertRaises(RuntimeError):
            sync.merge("Nagram/SettingsUI/Example.swift", b"base\n", b"ours\nours\n", b"upstream\n", reviewer)

    def test_review_includes_upstream_changes_even_if_merge_omitted_them(self):
        reviewer = sync.Reviewer()
        with patch.object(reviewer, "ask", return_value={"decision": "approve"}) as ask:
            sync.review_changes({}, reviewer, {"Nagram/test.swift": "required upstream behavior"})
        self.assertIn("required upstream behavior", ask.call_args.args[1]["diff"])

    def test_blocked_or_secret_model_output_is_not_applied(self):
        for result in ({"decision": "block"}, {"decision": "merge", "content": "APP_ID = 12345678"}):
            reviewer = sync.Reviewer()
            with patch.object(reviewer, "ask", return_value=result), self.assertRaises(RuntimeError):
                sync.merge("Nagram/test.swift", b"a\n", b"b\n", b"c\n", reviewer)

    def test_delete_modify_fails_closed(self):
        with self.assertRaises(RuntimeError):
            sync.merge("Nagram/test.swift", b"a\n", b"b\n", None, sync.Reviewer())

    def test_layout_sync_keeps_localization_used_by_downstream(self):
        merged = sync.retain_localization_keys(b'"Legacy" = "Old";\n"Shared" = "Before";\n', b'"Shared" = "After";\n"Added" = "New";\n')
        self.assertIn(b'"Legacy" = "Old";', merged)
        self.assertIn(b'"Shared" = "After";', merged)
        self.assertNotIn(b'"Shared" = "Before";', merged)

    def test_free_request_has_no_paid_fallback(self):
        response = {"choices": [{"finish_reason": "stop", "message": {"content": '{"decision":"approve"}'}}]}
        with patch.dict("os.environ", {"OPENROUTER_API_KEY": "private-test"}), patch.object(sync.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())) as call:
            self.assertEqual(sync.Reviewer().ask("Review", {"source": "public"})["decision"], "approve")
        body = json.loads(call.call_args.args[0].data)
        self.assertEqual(body["model"], "openrouter/free")
        self.assertEqual(body["provider"]["max_price"], {"prompt": 0, "completion": 0})
        self.assertNotIn("models", body)

    def test_truncated_model_output_fails_closed(self):
        response = {"choices": [{"finish_reason": "length", "message": {"content": '{"decision":"approve"}'}}]}
        with patch.dict("os.environ", {"OPENROUTER_API_KEY": "private-test"}), patch.object(sync.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())), self.assertRaises(RuntimeError):
            sync.Reviewer().ask("Review", {})

    def test_daily_budget(self):
        reviewer = sync.Reviewer()
        reviewer.calls = sync.MAX_CALLS
        with self.assertRaises(RuntimeError):
            reviewer.ask("Review", {})

    def test_empty_dispatch_response(self):
        with patch.object(sync.urllib.request, "urlopen", return_value=io.BytesIO(b"")):
            self.assertEqual(sync.api(sync.REPO, "/dispatches", {}), {})

    def test_changed_preference_and_settings_row_blocked(self):
        path = "Nagram/Settings/NagramSettings.swift"
        if Path(path).exists():
            content = Path(path).read_bytes()
            replacement = content.replace(b"@NagramDefault(", b"@RemovedDefault(", 1)
            with self.assertRaises(RuntimeError):
                sync.validate_changes({path: replacement})
        path = "Nagram/SettingsUI/NagramSettingsController.swift"
        if Path(path).exists():
            content = Path(path).read_bytes()
            with self.assertRaises(RuntimeError):
                sync.validate_changes({path: content.replace(b".toggle(titleKey:", b".removed(titleKey:", 1)})

    def test_publication_never_overwrites_concurrent_work(self):
        proposal = {"parent": "old", "upstream": "new", "changes": {"Nagram/test.swift": "YQo="}}
        with patch.object(Path, "read_text", return_value=json.dumps(proposal)), patch.object(sync, "api", return_value={"sha": "changed"}) as api:
            with self.assertRaises(RuntimeError):
                sync.publish()
        self.assertEqual(api.call_count, 1)

    def test_failed_pre_upload_release_is_preserved_for_audit(self):
        run = {"id": 12, "head_sha": "source", "status": "completed", "conclusion": "failure"}
        responses = [{"workflow_runs": [run]}, {"jobs": [{"steps": [
            {"name": "Upload signed IPA to App Store Connect", "conclusion": "skipped"},
            {"name": "Check whether a simulator artifact can stay private", "conclusion": "skipped"}]}]}]
        with patch.object(sync, "api", side_effect=responses), patch.object(sync, "blob", return_value=b'{"nagram_revision":"pin"}'):
            self.assertEqual(list(sync.source_builds("pin")), [run])

    def test_simulator_run_does_not_count_as_signed_release(self):
        run = {"display_title": "Build t. [simulator]"}
        with patch.object(sync, "api", return_value={"workflow_runs": [run]}):
            self.assertEqual(list(sync.source_builds("pin")), [])


if __name__ == "__main__":
    unittest.main()
