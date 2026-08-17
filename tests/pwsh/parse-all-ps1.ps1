#!/usr/bin/env pwsh
# Parses every *.ps1 in -Path with the real PowerShell parser and fails on any
# parse error. `report.ps1` shipped a ParserError for three releases: the file
# never parsed, so not one line of it ever ran, and nothing in CI opened it.
# This is the cheap check that would have caught it in seconds.
#
# Deliberate failure modes, both of which are how this class of bug survives:
#   - a file that reports "ok" without having been opened;
#   - a glob that matches nothing and passes.
# Hence: discovery by glob (never a hardcoded list that goes stale when a
# seventh pair lands), and zero matches is a failure.
#
# Run via tests/pwsh/parse-all-ps1.sh, which picks direct pwsh or Docker.
param(
    [string]$Path = "scripts"
)

$ErrorActionPreference = "Stop"

$dir   = (Resolve-Path -LiteralPath $Path).Path
$files = @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name)

if ($files.Count -eq 0) {
    Write-Host "FAIL: no *.ps1 found under $dir - the glob matched nothing"
    exit 1
}

$failed = 0
foreach ($f in $files) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $failed++
        Write-Host "FAIL $($f.Name)"
        foreach ($e in $errors) {
            Write-Host ("  line {0} col {1}: {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message)
        }
    } else {
        Write-Host "ok   $($f.Name)"
    }
}

Write-Host "parsed $($files.Count) file(s) under $dir; $failed with parse errors"
if ($failed -gt 0) { exit 1 }
exit 0
