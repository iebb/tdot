import importlib.util
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sync", Path(__file__).parents[1] / "sync-upstream.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def test_protected_paths(self):
        for path in (".env", ".github/workflows/build.yml", "ci/build.sh", "Nagram/../../.env", "Telegram/key.p8", "/Nagram/file.swift", "CLAUDE.md", "AGENTS.md", "build-system/appstore-configuration.json", "Nagram/.git/config", "."):
            self.assertFalse(sync.allowed(path))
        self.assertTrue(sync.allowed("submodules/TelegramUI/Chat.swift"))
        for path in ("MODULE.bazel", "MODULE.bazel.lock", ".bazelrc", ".gitmodules", "build-system/Make/Make.py", "NewLibrary/BUILD"):
            self.assertTrue(sync.allowed(path))

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

    def test_delete_modify_preserves_overlay_automatically(self):
        self.assertEqual(sync.merge("Nagram/test.swift", b"base\n", b"overlay\n", None, sync.Reviewer()), b"overlay\n")
        self.assertIsNone(sync.merge("Nagram/RemovedBadge.swift", b"base\n", None, b"upstream\n", sync.Reviewer()))
        self.assertIsNone(sync.merge("Nagram/obsolete.swift", b"base\n", b"base\n", None, sync.Reviewer()))

    def test_binary_assets_sync_and_keep_modified_branding(self):
        self.assertEqual(sync.merge("Telegram/icon.png", b"\0base", b"\0base", b"\0new", sync.Reviewer()), b"\0new")
        self.assertEqual(sync.merge("Telegram/icon.png", b"\0base", b"\0tdot", b"\0new", sync.Reviewer()), b"\0tdot")
        self.assertIn("Binary asset", sync.text_delta(b"\0old", b"\0new"))

    def plan(self, base, ours, upstream, hints=()):
        content = {}
        def tree(files):
            entries = {}
            for path, value in files.items():
                mode, data = value if isinstance(value, tuple) else ("100644", value)
                sha = data.decode() if mode == "160000" else hashlib.sha1(data).hexdigest()
                content[sha] = data
                entries[path] = {"path": path, "mode": mode, "sha": sha, "type": "commit" if mode == "160000" else "blob"}
            return entries
        trees = {"base": tree(base), "head": tree(ours), "latest": tree(upstream)}
        with patch.object(sync, "snapshot", side_effect=lambda repo, rev: trees[rev]), patch.object(sync, "source_blob", side_effect=lambda repo, sha: content[sha]), patch.object(sync, "api", return_value={"status": "diverged", "files": list(hints)}):
            return sync.plan_changes("base", "latest", "head", sync.Reviewer())

    def test_guidance_edit_never_blocks_app_or_infrastructure_sync(self):
        before = {"CLAUDE.md": b"old instructions", "MODULE.bazel": b"old dependency", "Nagram/new.swift": b"old"}
        upstream = dict(before, **{"CLAUDE.md": b"untrusted instructions", "MODULE.bazel": b"new dependency", "Nagram/new.swift": b"new"})
        changes, modes, renames, deltas = self.plan(before, before, upstream)
        self.assertNotIn("CLAUDE.md", changes)
        self.assertEqual(changes["MODULE.bazel"], b"new dependency")
        self.assertEqual(changes["Nagram/new.swift"], b"new")

    def test_rename_carries_downstream_overlay_and_deletes_old_path(self):
        changes, modes, renames, deltas = self.plan({"Nagram/Old.swift": b"base\n"}, {"Nagram/Old.swift": b"overlay\n"}, {"Nagram/New.swift": b"base\n"})
        self.assertEqual(changes, {"Nagram/New.swift": b"overlay\n", "Nagram/Old.swift": None})
        self.assertEqual(renames, {"Nagram/Old.swift": "Nagram/New.swift"})

    def test_renamed_removed_badge_stays_removed(self):
        changes, _, _, _ = self.plan({"Nagram/Badge.swift": b"badge\n"}, {}, {"Nagram/NewBadge.swift": b"badge\n"})
        self.assertEqual(changes, {})

    def test_large_snapshot_is_not_limited_to_compare_file_list(self):
        after = {f"Nagram/Source{i}.swift": b"public code\n" for i in range(320)}
        changes, _, _, _ = self.plan({}, {}, after)
        self.assertEqual(len(changes), 320)

    def test_submodule_and_executable_modes_follow_upstream(self):
        path = "third-party/library"
        changes, modes, _, _ = self.plan({path: ("160000", b"a" * 40)}, {path: ("160000", b"a" * 40)}, {path: ("160000", b"b" * 40), "build-system/new.sh": ("100755", b"echo build\n")})
        self.assertEqual(changes[path], b"b" * 40)
        self.assertEqual(modes[path], "160000")
        self.assertEqual(modes["build-system/new.sh"], "100755")

    def test_edited_rename_merges_overlay_with_upstream_functionality(self):
        base = b"a\nb\nc\nd\ne\n"
        hints = [{"status": "renamed", "previous_filename": "Nagram/Old.swift", "filename": "Nagram/New.swift"}]
        changes, _, _, _ = self.plan({"Nagram/Old.swift": base}, {"Nagram/Old.swift": b"A\nb\nc\nd\ne\n"}, {"Nagram/New.swift": b"a\nb\nc\nd\nE\n"}, hints)
        self.assertEqual(changes["Nagram/New.swift"], b"A\nb\nc\nd\nE\n")

    def test_toolchain_sync_preserves_downstream_release_version(self):
        with patch.object(Path, "read_text", return_value='{"app":"1.0.0","xcode":"old","tdot_revision":7}'):
            result = sync.synced_versions({"app": "13.0.1", "xcode": "new", "unknown_identity": "upstream"}, "new-pin")
        self.assertEqual(result, {"app": "1.0.0", "xcode": "new", "tdot_revision": 7, "nagram_revision": "new-pin"})

    def test_candidate_preserves_executable_and_symlink_modes(self):
        cwd = Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            try:
                os.chdir(folder)
                proposal = {"parent": "head", "upstream": "pin", "changes": {"Nagram/run.sh": "ZWNobyBvaw==", "Nagram/link": "cnVuLnNo"}, "modes": {"Nagram/run.sh": "100755", "Nagram/link": "120000"}}
                Path("sync-proposal.json").write_text(json.dumps(proposal))
                with patch.dict("os.environ", {"GITHUB_SHA": "head"}):
                    sync.apply_proposal()
                self.assertTrue(Path("Nagram/run.sh").stat().st_mode & 0o111)
                self.assertTrue(Path("Nagram/link").is_symlink())
                self.assertEqual(Path("Nagram/link").read_text(), "echo ok")
            finally:
                os.chdir(cwd)

    def test_private_or_escaping_symlinks_rejected(self):
        for data in (b"../.env", b"../../outside", b"/etc/passwd"):
            with self.assertRaises(RuntimeError):
                sync.validate_changes({"Nagram/link": data}, {"Nagram/link": "120000"})

    def test_reviewer_disagreement_is_retried_with_another_free_model(self):
        reviewer = sync.Reviewer()
        with patch.object(reviewer, "request", side_effect=[{"decision": "block", "content": "combine adjacent edits"}, {"decision": "merge", "content": "combined"}]) as request:
            self.assertEqual(reviewer.ask("Resolve", {})["content"], "combined")
        self.assertEqual(request.call_args.args[2], 1)
        self.assertIn("correctionRequired", request.call_args.args[1])

    def test_source_review_repairs_omitted_behavior_without_human_approval(self):
        changes = {"Nagram/Example.swift": b"overlay\n"}
        reviewer = sync.Reviewer()
        answers = [{"decision": "repair", "repairs": [{"path": "Nagram/Example.swift", "before": "overlay\n", "after": "overlay + upstream\n"}]}, {"decision": "approve"}]
        with patch.object(reviewer, "ask", side_effect=answers):
            sync.review_changes(changes, reviewer, {"Nagram/Example.swift": "upstream feature"})
        self.assertEqual(changes["Nagram/Example.swift"], b"overlay + upstream\n")

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
        self.assertTrue(all(model.endswith(":free") for model in body["models"]))
        self.assertEqual(body["provider"]["max_price"], {"prompt": 0, "completion": 0})
        self.assertEqual(body["tool_choice"]["function"]["name"], "submit_merge_decision")

    def test_forced_tool_is_parsed_as_data_without_execution(self):
        response = {"choices": [{"finish_reason": "tool_calls", "message": {"tool_calls": [
            {"function": {"name": "submit_merge_decision", "arguments": '{"decision":"approve","content":""}'}}]}}]}
        with patch.dict("os.environ", {"OPENROUTER_API_KEY": "private-test"}), patch.object(sync.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())):
            self.assertEqual(sync.Reviewer().ask("Review", {})["decision"], "approve")

    def test_unexpected_model_tool_is_rejected(self):
        response = {"choices": [{"finish_reason": "tool_calls", "message": {"tool_calls": [
            {"function": {"name": "run_command", "arguments": '{}'}}]}}]}
        with patch.dict("os.environ", {"OPENROUTER_API_KEY": "private-test"}), patch.object(sync.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())), self.assertRaises(RuntimeError):
            sync.Reviewer().ask("Review", {})

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

    def test_candidate_cannot_apply_to_a_different_checkout(self):
        proposal = {"parent": "reviewed-source", "changes": {"Nagram/test.swift": "YQo="}}
        with patch.object(Path, "read_text", return_value=json.dumps(proposal)), patch.dict("os.environ", {"GITHUB_SHA": "different-source"}), self.assertRaises(RuntimeError):
            sync.apply_proposal()

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
