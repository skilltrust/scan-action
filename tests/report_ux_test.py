"""Renderer contract tests, run by Bats; no network or third-party packages."""
import copy
import importlib.util
import itertools
from pathlib import Path
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("renderer", ROOT / "scripts/render.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


def finding(line, description, severity="HIGH", **fields):
    return dict(rule_id="SD-004", file_path="AGENTS.md", line=line,
                description=description, severity=severity, **fields)


class ReportUX(unittest.TestCase):
    def setUp(self):
        self.args = SimpleNamespace(delta="true", event="pull_request", scope=".",
                                    exit_code="2", report_only="false", warn_below="true",
                                    fail_no_surface="false")
        self.old = finding(40, "existing critical", "CRITICAL")
        self.new = finding(9, "new credential access", "CRITICAL", remediation="Remove credential access.")
        self.scan = dict(findings=[self.old, finding(17, "shifted finding"), self.new],
                         axes={"security": {"grade": "F"}}, files_scanned=4)
        self.delta = dict(new_findings=[self.new], resolved_findings=[
            finding(3, "base-only one"), finding(5, "base-only two"),
            finding(8, "base-only three"), finding(12, "base-only four")], per_axis={})

    def render(self):
        return renderer.render(self.scan, self.delta, {"SD-004"}, "pr_comment", self.args)

    def test_asymmetric_buckets_and_priority(self):
        text = self.render()
        self.assertIn("1 new in this PR · 2 already on base · 4 fixed by this PR", text)
        self.assertLess(text.index("PR is blocked"), text.index("1 new in this PR"))
        self.assertLess(text.index("new credential access"), text.index("existing critical"))
        self.assertLess(text.index("Fixed by this PR (4)"), text.index("Grades for"))
        self.assertLess(text.index("Grades for"), text.index("| Scope |"))
        self.assertIn("<summary>Already on base (2)</summary>", text)
        self.assertIn("not previous runs", text)
        self.assertIn("(base location)", text)
        self.assertNotIn("Resolved", text)

    def test_identity_uses_description_line_path_rule_not_severity_or_diagnosis(self):
        other_description = finding(9, "different description")
        other_line = finding(10, "new credential access")
        other_path = dict(self.new, file_path="CLAUDE.md")
        other_rule = dict(self.new, rule_id="SD-007")
        self.scan["findings"] = [other_description, other_line, other_path, other_rule,
                                 dict(self.new, severity="LOW", diagnosis="different diagnosis")]
        new, existing = renderer.partition(self.scan["findings"], self.delta)
        self.assertEqual([f["severity"] for f in new], ["LOW"])
        self.assertEqual(existing, [other_description, other_line, other_path, other_rule])

    def test_duplicate_occurrences_are_subtracted_one_for_one(self):
        self.scan["findings"] = [self.new, self.new, self.new, self.old]
        self.assertIn("1 new in this PR · 3 already on base", self.render())

    def test_off_unavailable_and_non_pr_never_claim_delta_counts(self):
        for mode, event, delta, reason in [
            ("false", "pull_request", self.delta, "Comparison off"),
            ("true", "pull_request", None, "Comparison unavailable"),
            ("true", "pull_request", {}, "Comparison unavailable"),
            ("true", "pull_request", dict(new_findings=[self.old, self.old], resolved_findings=[]), "Comparison unavailable"),
            ("true", "schedule", self.delta, "Comparison unavailable"),
        ]:
            with self.subTest(mode=mode, event=event, delta=delta):
                self.args.delta, self.args.event, self.delta = mode, event, delta
                text = self.render()
                self.assertIn("### Current findings (3)", text)
                self.assertIn(reason, text)
                self.assertNotIn("### New in this PR", text)
                self.assertNotIn("### Fixed by this PR", text)
                if event == "schedule":
                    self.assertNotIn("PR is", text)

    def test_policy_matrix_uses_full_head_not_new_findings(self):
        self.delta["new_findings"] = []
        for code, report_only, warn_below in itertools.product("012", (True, False), (True, False)):
            with self.subTest(code=code, report_only=report_only, warn_below=warn_below):
                self.args.exit_code = code
                self.args.report_only = str(report_only).lower()
                self.args.warn_below = str(warn_below).lower()
                self.scan["findings"] = [] if code == "0" else [self.old]
                blocked = not report_only and (code == "2" or (code == "1" and not warn_below))
                text = self.render()
                self.assertIn("PR is blocked" if blocked else "PR is not blocked", text)
                if report_only:
                    self.assertIn("not blocked — report-only mode", text)
                if code == "0":
                    self.assertIn("Clean — no findings", text)

    def test_no_surface_policy_precedes_report_only(self):
        self.scan = dict(no_agent_surface=True, findings=[])
        self.args.exit_code = "0"
        self.delta = None
        for report_only, fail in itertools.product((True, False), repeat=2):
            self.args.report_only = str(report_only).lower()
            self.args.fail_no_surface = str(fail).lower()
            text = self.render()
            self.assertIn("PR is blocked" if fail else "PR is not blocked", text)
            self.assertIn("Nothing was checked", text)
            self.assertNotIn("Clean", text)
            self.assertNotIn("| Security |", text)

    def test_no_run_history_and_null_empty_delta(self):
        # A finding introduced and removed inside this PR is in neither
        # snapshot: no record of it may appear, including after a rerender.
        self.render()
        self.scan["findings"] = []
        self.args.exit_code = "0"
        self.delta = dict(new_findings=None, resolved_findings=None, per_axis={})
        text = self.render()
        self.assertIn("0 new in this PR · 0 already on base · 0 fixed by this PR", text)
        self.assertNotIn("new credential access", text)

    def test_hostile_data_in_all_buckets_is_inert_and_total_head_cap_is_ten(self):
        hostile = '</details><script>alert(1)</script> ![x](https://evil.invalid) @everyone\n::error::boom'
        new = [finding(i, hostile, remediation=hostile) for i in range(7)]
        old = [finding(i + 20, hostile) for i in range(8)]
        fixed = [finding(i + 40, hostile) for i in range(12)]
        self.scan["findings"] = old + new
        self.delta = dict(new_findings=copy.deepcopy(new), resolved_findings=fixed, per_axis={})
        before = copy.deepcopy(self.scan)
        text = self.render()
        self.assertEqual(text.count("  - Explanation:"), 10)
        self.assertEqual(text.count("  - Previous finding:"), 10)
        self.assertIn("Showing 3 of 8 findings", text)
        self.assertIn("Showing 10 of 12 fixed findings", text)
        self.assertNotIn("<script>", text)
        self.assertNotIn("https://evil", text)
        self.assertNotIn("@everyone", text)
        self.assertEqual(text.count("</details>"), 2)
        self.assertEqual(before, self.scan)


if __name__ == "__main__":
    unittest.main()
