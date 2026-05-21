$ErrorActionPreference = "Stop"

$templateDir = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
$scan = $env:INPUT_SCAN_JSON
$out  = Join-Path $env:RUNNER_TEMP "comment.md"

# Re-use python (preinstalled on windows-latest) for parity with bash variant.
$py = @"
import json, os, sys
data = json.load(open(sys.argv[1]))
axes = data.get('axes') or {}
grades = sorted([v.get('grade','') for v in axes.values()]) if axes else []
worst = grades[-1] if grades else '—'
findings = data.get('findings') or []
detector_version = data.get('version') or 'unknown'

axis_rows = '\n'.join(
    f'| {k} | {v.get("grade","")} |' for k, v in sorted(axes.items())
) if axes else '| _no axes_ | — |'

if not findings:
    findings_block = '_No findings._'
else:
    rows = []
    for f in sorted(findings, key=lambda x: (x.get('severity',''), x.get('rule_id','')))[:10]:
        rows.append(f"- ``{f.get('rule_id','')}`` {f.get('axis','')} · ``{f.get('file_path','')}:{f.get('line',0)}`` — {f.get('description','')}")
    findings_block = f"**Findings ({len(findings)}):**\n" + '\n'.join(rows)

src = open(sys.argv[2]).read()
out = (src
    .replace('__GRADE__', worst)
    .replace('__AXIS_ROWS__', axis_rows)
    .replace('__FINDINGS_BLOCK__', findings_block)
    .replace('__DETECTOR_VERSION__', detector_version))
open(sys.argv[3], 'w', encoding='utf-8').write(out)
"@
python -c $py $scan (Join-Path $templateDir 'comment.md.tmpl') $out
Write-Host "render-comment.ps1: comment.md written to $out"
