#!/usr/bin/env python3
"""Render one hostile-data-safe scan report for Summary and PR comment."""

import argparse
import html
import json
import os
import re
import unicodedata
from collections import Counter
from pathlib import Path

MARKER = "<!-- skilltrust:action:v1 -->"
AXES = (
    ("security", "Security"),
    ("permission_hygiene", "Permission hygiene"),
    ("transparency", "Transparency"),
)
SEVERITY = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}
MAX_FINDINGS = 10
MAX_TEXT = 500
MAX_WARNINGS = 10
BASE_URL = "https://skilltrust.app"
UTM = "utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch"


def safe(value, limit=MAX_TEXT):
    """Make untrusted scalar inert in Markdown, HTML, mentions and log output."""
    raw = str(value if value is not None else "")
    raw = "".join(" " if unicodedata.category(char) in {"Cc", "Cf", "Cs"} else char for char in raw)
    text = " ".join(raw.split())
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    text = html.escape(text, quote=True)
    escaped = re.sub(r"([\\`*_{}\[\]()#+.!|>~-])", r"\\\1", text)
    return escaped.replace("@", "&#64;").replace("://", ":&#47;&#47;")


def scalar(obj, key, default=""):
    value = obj.get(key, default) if isinstance(obj, dict) else default
    return value if isinstance(value, (str, int, float, bool)) else default


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("result root is not an object")
    return value


def load_published(path):
    return {
        line.strip()
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def site_url(path, content):
    return f"{BASE_URL}{path}?{UTM}&utm_content={content}"


def rule_label(rule_id, published, content):
    if rule_id in published and re.fullmatch(r"SD-0\d\d", rule_id):
        return f"[{rule_id}]({site_url('/rules/' + rule_id.lower(), content)})"
    return safe(rule_id, 32) or "unknown rule"


def effective(finding):
    value = str(finding.get("effective_severity") or finding.get("severity") or "INFO").upper()
    return value if value in SEVERITY else "INFO"


def finding_key(item):
    index, finding = item
    line = finding.get("line")
    return (
        SEVERITY[effective(finding)],
        str(finding.get("rule_id", "")),
        str(finding.get("file_path", "")),
        line if isinstance(line, int) else 0,
        index,
    )


def outcome(scan, exit_code, report_only, warn_below, fail_no_surface):
    if any(value not in {"true", "false"} for value in
           (report_only, warn_below, fail_no_surface)):
        return "will fail — invalid boolean policy input"
    if exit_code == "0" and scan.get("no_agent_surface") is True:
        return ("will fail — no agent files checked; fail-on-no-agent-surface is enabled"
                if fail_no_surface == "true" else "passes — no agent files checked")
    if report_only == "true" and exit_code in {"0", "1", "2"}:
        return "passes — report-only mode"
    if exit_code == "0":
        return "passes — no findings"
    if exit_code == "2":
        return "will fail — configured threshold reached"
    if exit_code == "1":
        return ("passes — findings below threshold" if warn_below == "true" else
                "will fail — findings below threshold; warn-on-below-threshold is disabled")
    return "status unavailable — check the job result"


def delta_identity(finding):
    # Detector v0.10.0 pkg/delta.findingKey uses these fields (hashing only
    # description). Compare the source fields, not a new fingerprint scheme.
    # Its line-shift pairing has already happened in new_findings.
    return tuple(finding.get(key, default) for key, default in (
        ("rule_id", ""), ("file_path", ""), ("line", 0), ("description", "")))


def valid_delta_finding(finding):
    return (
        isinstance(finding, dict) and
        all(isinstance(finding.get(field), str) for field in
            ("rule_id", "description", "file_path", "diagnosis", "remediation")) and
        finding.get("severity") in SEVERITY and
        finding.get("effective_severity") in SEVERITY and
        type(finding.get("line")) is int and finding["line"] >= 0
    )


def partition(findings, delta):
    """Subtract the detector's new occurrences; duplicate counts matter."""
    for field in ("new_findings", "resolved_findings"):
        if field not in delta or (delta[field] is not None and not isinstance(delta[field], list)):
            raise ValueError("invalid delta findings")
    new_findings = delta.get("new_findings") or []
    resolved_findings = delta.get("resolved_findings") or []
    if not all(valid_delta_finding(f) for f in new_findings + resolved_findings):
        raise ValueError("invalid delta finding")
    head_identities = {delta_identity(f) for f in findings}
    if any(delta_identity(f) in head_identities for f in resolved_findings):
        raise ValueError("resolved finding is still present in head")
    budget = Counter(delta_identity(f) for f in new_findings)
    new, existing = [], []
    for finding in findings:
        key = delta_identity(finding)
        if budget[key]:
            new.append(finding)
            budget[key] -= 1
        else:
            existing.append(finding)
    if any(budget.values()):
        raise ValueError("delta does not match head")
    return new, existing


def axis_table(scan, delta):
    axes = scan.get("axes") if isinstance(scan.get("axes"), dict) else {}
    per_axis = delta.get("per_axis") if isinstance(delta, dict) and isinstance(delta.get("per_axis"), dict) else {}
    rows = ["| Axis | Grade | Δ |", "|---|---:|---|"] if delta else ["| Axis | Grade |", "|---|---:|"]
    for key, label in AXES:
        current = axes.get(key) if isinstance(axes.get(key), dict) else {}
        grade = safe(scalar(current, "grade", "—"), 4)
        if delta:
            change = per_axis.get(key) if isinstance(per_axis.get(key), dict) else {}
            old = safe(scalar(change, "Old"), 4)
            new = safe(scalar(change, "New", scalar(current, "grade", "—")), 4)
            direction = scalar(change, "Direction")
            movement = "—" if direction == "same" or not old else f"{old} → {new}"
            rows.append(f"| {label} | {grade} | {movement} |")
        else:
            rows.append(f"| {label} | {grade} |")
    return rows


def render_finding(finding, published, content, resolved=False):
    severity = effective(finding)
    rule = rule_label(str(scalar(finding, "rule_id")), published, content)
    path = safe(scalar(finding, "file_path", "unknown file"), 300)
    line = scalar(finding, "line", 0)
    location = f"{path}:{line}" if isinstance(line, int) and line > 0 else path
    explanation = scalar(finding, "diagnosis") or scalar(finding, "description") or "No explanation supplied."
    remediation = scalar(finding, "remediation") or "No remediation supplied."
    prefix = "Fixed" if resolved else severity
    if resolved:
        return [f"- **{prefix}** · {rule} · {location} (base location)",
                f"  - Previous finding: {safe(explanation)}"]
    return [
        f"- **{prefix}** · {rule} · {location}",
        f"  - Explanation: {safe(explanation)}",
        f"  - Remediation: {safe(remediation)}",
    ]


def render(scan, delta, published, content, args):
    findings = scan.get("findings") if isinstance(scan.get("findings"), list) else []
    new, existing = [], []
    if args.delta != "true" or args.event != "pull_request":
        delta = None
    if delta is not None:
        try:
            new, existing = partition(findings, delta)
            resolved = delta.get("resolved_findings") or []
            if not isinstance(resolved, list) or not all(isinstance(f, dict) for f in resolved):
                raise ValueError("invalid fixed findings")
        except (TypeError, AttributeError, ValueError):
            delta = None
    no_surface = scan.get("no_agent_surface") is True
    heading = ("## SkillTrust — Nothing was checked" if no_surface else
               f"## SkillTrust — {len(findings)} current {'issue' if len(findings) == 1 else 'issues'}" if findings else
               "## SkillTrust — Clean — no findings")
    lines = [heading, "", f"**SkillTrust check {outcome(scan, args.exit_code, args.report_only, args.warn_below, args.fail_no_surface)}.**"]
    if args.event == "pull_request":
        lines.extend(["", "If this check is required, failure blocks merging."])
    if delta is not None:
        lines.extend(["", f"**Current: {len(new)} new in this PR · {len(existing)} already on base**  ",
                      f"**Fixed by this PR: {len(resolved)}**",
                      "", "Current base vs head, not previous runs."])
    else:
        reason = "Comparison off" if args.delta != "true" else "Comparison unavailable"
        lines.extend(["", f"{reason}; new, existing and fixed status is unknown."])
    if no_surface:
        lines.extend(["", "No supported agent configuration files were found. No grades are shown; this is not a clean verdict.",
                      "", "**Next:** Check the selected path and supported agent files before relying on this scan."])
    elif findings:
        lines.extend(["", "**Next:** Review CRITICAL/HIGH first, including those already on base. Policy uses all current findings."])
    else:
        lines.extend(["", "**Next:** No finding remediation is needed in the scanned scope. Review the rest of the PR as usual."])

    remaining = MAX_FINDINGS
    groups = [("New in this PR", new, False), ("Already on base", existing, True)] if delta is not None else [("Current findings", findings, False)]
    if not no_surface:
        for label, items, collapsed in groups:
            shown = [f for _, f in sorted(enumerate(items), key=finding_key)[:remaining]]
            remaining -= len(shown)
            if collapsed:
                counts = Counter(effective(f) for f in items)
                severe = ", ".join(f"{counts[s]} {s}" for s in ("CRITICAL", "HIGH") if counts[s])
                detail = f" · includes {severe}" if severe else ""
                lines.extend(["", "<details>", f"<summary>{label} ({len(items)}{detail})</summary>", ""])
            else:
                lines.extend(["", f"### {label} ({len(items)})", ""])
            lines.append(f"Showing {len(shown)} of {len(items)} findings." if items else "_None._")
            lines.append("")
            for finding in shown:
                lines.extend(render_finding(finding, published, content))
            if collapsed:
                lines.extend(["", "</details>"])
    if delta is not None:
        shown = [f for _, f in sorted(enumerate(resolved), key=finding_key)[:MAX_FINDINGS]]
        lines.extend(["", f"### Fixed by this PR ({len(resolved)})", "",
                      "Present on base, absent from head.", "",
                      f"Showing {len(shown)} of {len(resolved)} fixed findings." if resolved else "_None._", ""])
        for finding in shown:
            lines.extend(render_finding(finding, published, content, resolved=True))

    warnings = scan.get("warnings") if isinstance(scan.get("warnings"), list) else []
    if warnings or (args.delta == "true" and args.event == "pull_request" and not delta):
        lines.extend(["", "### Warnings", ""])
        if args.delta == "true" and args.event == "pull_request" and not delta:
            lines.append("- Delta unavailable; the complete head result and gate remain authoritative.")
        for warning in warnings[:MAX_WARNINGS]:
            lines.append(f"- {safe(warning)}")
        if len(warnings) > MAX_WARNINGS:
            lines.append(f"- Showing {MAX_WARNINGS} of {len(warnings)} engine warnings.")

    if not no_surface:
        lines.extend(["", "### Grades for the current scan", "",
                      "Grades describe findings, not whether this check fails. The policy above determines the check result.",
                      "", *axis_table(scan, delta)])
    lines.extend(["", "<details>", "<summary>Scan details and scope</summary>", "", "| Run | Value |", "|---|---|"])
    mode = "Report only" if args.report_only == "true" else "Gate policy"
    checkout = "Pull request head" if args.event == "pull_request" else "Workflow checkout"
    lines.extend(
        [
            f"| Scope | {safe(args.scope, 300)} |",
            f"| Checkout | {checkout} |",
            f"| Engine | skill-detector {safe(scalar(scan, 'version', 'unknown'), 40)} |",
            f"| Mode | {mode} |",
            f"| Files scanned | **{safe(scalar(scan, 'files_scanned', 0), 20)}** |",
        ]
    )
    if args.delta == "true" and args.event == "pull_request":
        lines.append(f"| Comparison | {'Available' if delta else '**Unavailable** — head result and policy unchanged'} |")
    elif args.delta == "true":
        lines.append("| Comparison | Unavailable — delta runs on pull requests only |")
    else:
        lines.append("| Comparison | Off |")

    lines.extend(
        [
            "",
            "### Supported boundary",
            "",
            "SkillTrust checks supported agent configuration files in the selected scope. A clean result means no supported rule matched; it is not a guarantee that the repository is safe.",
            "",
            "</details>",
            "",
            "### Complete result",
            "",
            "The validated, unmodified JSON is retained at the `scan-json-path` output. To retrieve it after the job, upload that path with `actions/upload-artifact`; see the Action docs.",
            "",
            "---",
            f"[SkillTrust Action docs]({site_url('/docs/action', content)}) · scan-action@v1 · Detector {safe(scalar(scan, 'version', 'unknown'), 40)}",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan", required=True)
    parser.add_argument("--published", required=True)
    parser.add_argument("--comment", required=True)
    parser.add_argument("--summary", default="")
    parser.add_argument("--scope", default=".")
    parser.add_argument("--event", default="unknown")
    parser.add_argument("--exit-code", default="")
    parser.add_argument("--report-only", default="false")
    parser.add_argument("--warn-below", default="true")
    parser.add_argument("--fail-no-surface", default="false")
    parser.add_argument("--delta-enabled", dest="delta", action="store_const", const="true")
    parser.set_defaults(delta="false")
    args = parser.parse_args()

    scan = load_json(args.scan)
    delta_path = os.environ.get("INPUT_DELTA_JSON", "")
    try:
        delta = load_json(delta_path) if args.delta == "true" and delta_path and os.path.isfile(delta_path) else None
    except (OSError, ValueError):
        delta = None
    published = load_published(args.published)
    comment = MARKER + "\n" + render(scan, delta, published, "pr_comment", args)
    summary = render(scan, delta, published, "job_summary", args)
    Path(args.comment).write_text(comment, encoding="utf-8")
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as handle:
            handle.write(summary)


if __name__ == "__main__":
    main()
