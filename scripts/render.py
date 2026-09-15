#!/usr/bin/env python3
"""Render one hostile-data-safe scan report for Summary and PR comment."""

import argparse
import html
import json
import os
import re
import unicodedata
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
    findings = scan.get("findings") if isinstance(scan.get("findings"), list) else []
    if scan.get("no_agent_surface") is True:
        return "Nothing checked — no grade" + (" — blocking" if fail_no_surface else " — nonblocking")
    if exit_code == "0" and not findings:
        return "Clean — no findings"
    if exit_code == "2":
        return "Threshold reached" + (" — nonblocking" if report_only else " — blocking")
    if exit_code == "1":
        return "Findings below threshold" + (" — nonblocking" if report_only or warn_below else " — blocking")
    return "Findings reported"


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
    prefix = "Resolved" if resolved else severity
    return [
        f"- **{prefix}** · {rule} · {location}",
        f"  - Explanation: {safe(explanation)}",
        f"  - Remediation: {safe(remediation)}",
    ]


def render(scan, delta, published, content, args):
    findings = scan.get("findings") if isinstance(scan.get("findings"), list) else []
    valid_findings = [(i, f) for i, f in enumerate(findings) if isinstance(f, dict)]
    shown = [f for _, f in sorted(valid_findings, key=finding_key)[:MAX_FINDINGS]]
    no_surface = scan.get("no_agent_surface") is True
    report_only = args.report_only == "true"
    warn_below = args.warn_below == "true"
    fail_no_surface = args.fail_no_surface == "true"
    heading = "## SkillTrust — Nothing was checked" if no_surface else "## SkillTrust scan"
    lines = [heading, "", "| Run | Value |", "|---|---|"]
    mode = "Report only" if report_only else "Gate policy"
    checkout = "Pull request head" if args.event == "pull_request" else "Push checkout"
    lines.extend(
        [
            f"| Scope | {safe(args.scope, 300)} |",
            f"| Checkout | {checkout} |",
            f"| Engine | skill-detector {safe(scalar(scan, 'version', 'unknown'), 40)} |",
            f"| Mode | {mode} |",
            f"| Outcome | **{outcome(scan, args.exit_code, report_only, warn_below, fail_no_surface)}** |",
            f"| Files scanned | **{safe(scalar(scan, 'files_scanned', 0), 20)}** |",
        ]
    )
    if args.delta == "true" and args.event == "pull_request":
        lines.append(f"| Comparison | {'Available' if delta else '**Unavailable** — head result and policy unchanged'} |")
    elif args.delta == "true":
        lines.append("| Comparison | Unavailable — delta runs on pull requests only |")
    else:
        lines.append("| Comparison | Off |")

    if no_surface:
        lines.extend(["", "No supported agent configuration files were found. No grades are shown; this is not a clean verdict."])
    else:
        lines.extend(["", "### Public axes", "", *axis_table(scan, delta)])

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
        lines.extend(["", f"### Findings ({len(findings)})", ""])
        if not findings:
            lines.append("_No findings._")
        else:
            lines.append(f"Showing {len(shown)} of {len(findings)} findings.")
            lines.append("")
            for finding in shown:
                lines.extend(render_finding(finding, published, content))

    resolved = delta.get("resolved_findings") if isinstance(delta, dict) and isinstance(delta.get("resolved_findings"), list) else []
    resolved = [item for item in resolved if isinstance(item, dict)]
    if resolved:
        resolved_shown = resolved[:MAX_FINDINGS]
        lines.extend(["", f"### Resolved ({len(resolved)})", "", f"Showing {len(resolved_shown)} of {len(resolved)} resolved findings.", ""])
        for finding in resolved_shown:
            lines.extend(render_finding(finding, published, content, resolved=True))

    lines.extend(
        [
            "",
            "### Supported boundary",
            "",
            "SkillTrust checks supported agent configuration files in the selected scope. A clean result means no supported rule matched; it is not a guarantee that the repository is safe.",
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
    delta = load_json(delta_path) if delta_path and os.path.isfile(delta_path) else None
    published = load_published(args.published)
    comment = MARKER + "\n" + render(scan, delta, published, "pr_comment", args)
    summary = render(scan, delta, published, "job_summary", args)
    Path(args.comment).write_text(comment, encoding="utf-8")
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as handle:
            handle.write(summary)


if __name__ == "__main__":
    main()
