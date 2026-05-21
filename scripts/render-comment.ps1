$ErrorActionPreference = "Stop"

$templateDir = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
$scan  = $env:INPUT_SCAN_JSON
$delta = $env:INPUT_DELTA_JSON
$out   = Join-Path $env:RUNNER_TEMP "comment.md"

$py = @"
import json, os, sys
scan = json.load(open(sys.argv[1]))
delta = json.load(open(sys.argv[2])) if sys.argv[2] and os.path.exists(sys.argv[2]) else None

axes = scan.get('axes') or {}
grades = sorted([v.get('grade','') for v in axes.values()]) if axes else []
worst = grades[-1] if grades else '—'
findings = scan.get('findings') or []
detector_version = scan.get('version') or 'unknown'

grade_delta = ''
why_block = ''
resolved_block = ''

if delta:
    per_axis = delta.get('per_axis') or {}
    olds = sorted([v.get('Old','') for v in per_axis.values() if v.get('Old')])
    if olds:
        grade_delta = f' (was {olds[-1]})'
    rows = []
    for k in sorted(per_axis):
        v = per_axis[k]
        head_grade = (axes.get(k) or {}).get('grade', v.get('New',''))
        if v.get('Direction') == 'same' or not v.get('Old'):
            d = '—'
        else:
            arrow = '↑' if v.get('Direction') == 'up' else '↓'
            d = f"{arrow} {v.get('Old')} → {v.get('New')}"
        rows.append(f'| {k} | {head_grade} | {d} |')
    axis_table = '| Axis | Grade | Δ |\n|------|-------|---|\n' + '\n'.join(rows)
    expl = delta.get('axis_explanations') or {}
    if expl:
        why_block = '**Why downgraded:**\n' + '\n'.join(f'- **{k}:** {expl[k]}' for k in sorted(expl))
    resolved = delta.get('resolved_findings') or []
    if resolved:
        resolved_block = f'**Resolved ({len(resolved)}):**\n' + '\n'.join(
            f"- ✅ ``{r.get('rule_id','')}`` {r.get('axis','')} — {r.get('description','')}" for r in resolved)
else:
    rows = [f'| {k} | {v.get("grade","")} |' for k, v in sorted(axes.items())]
    axis_table = '| Axis | Grade |\n|------|-------|\n' + ('\n'.join(rows) if rows else '| _no axes_ | — |')

if not findings:
    findings_block = '_No findings._'
else:
    rows = []
    for f in sorted(findings, key=lambda x: (x.get('severity',''), x.get('rule_id','')))[:10]:
        rows.append(f"- ``{f.get('rule_id','')}`` {f.get('axis','')} · ``{f.get('file_path','')}:{f.get('line',0)}`` — {f.get('description','')}")
    findings_block = f'**Findings ({len(findings)}):**\n' + '\n'.join(rows)

src = open(sys.argv[3]).read()
out = (src
    .replace('__GRADE__', worst)
    .replace('__GRADE_DELTA__', grade_delta)
    .replace('__AXIS_TABLE__', axis_table)
    .replace('__WHY_BLOCK__', why_block)
    .replace('__FINDINGS_BLOCK__', findings_block)
    .replace('__RESOLVED_BLOCK__', resolved_block)
    .replace('__DETECTOR_VERSION__', detector_version))
open(sys.argv[4], 'w', encoding='utf-8').write(out)
"@
python -c $py $scan ($delta -as [string]) (Join-Path $templateDir 'comment.md.tmpl') $out
Write-Host "render-comment.ps1: comment.md written to $out"
