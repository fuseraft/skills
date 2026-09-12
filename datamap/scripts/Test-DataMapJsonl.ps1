<#
.SYNOPSIS
Validates a datamap JSONL file: every line must be a JSON object carrying
exactly the ten datamap fields, with every field except `notes` non-blank.

.DESCRIPTION
Use this after Pass 1 (structural generation) and again after Pass 2 (notes
population) as the Pass 3 final check before CSV conversion. It never repairs
or rewrites the file - it only reports.

.PARAMETER Path
Path to the .jsonl file to validate.

.PARAMETER Quiet
Suppress the human-readable summary; print only the JSON result object.

.OUTPUTS
Prints a single JSON object to stdout:
  { "valid": bool, "path": string, "lineCount": int,
    "errors": [{"line": int, "message": string}, ...],
    "warnings": [{"line": int, "message": string}, ...] }

Exit code 0 when valid (zero errors), 1 when invalid, 2 on usage error.

.EXAMPLE
pwsh -File scripts/Test-DataMapJsonl.ps1 -Path ./datamap.jsonl
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DataMap.Common.ps1')

$result = Test-DataMapFile -Path $Path

$resolvedPath = [string](Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
if ([string]::IsNullOrEmpty($resolvedPath)) { $resolvedPath = $Path }

$output = [ordered]@{
    valid     = $result.Valid
    path      = $resolvedPath
    lineCount = $result.LineCount
    errors    = $result.Errors
    warnings  = $result.Warnings
}

if (-not $Quiet) {
    if ($result.Valid) {
        Write-Host "OK: $($result.LineCount) line(s) valid in $Path" -ForegroundColor Green
    }
    else {
        Write-Host "INVALID: $($result.Errors.Count) error(s) in $Path" -ForegroundColor Red
    }
    foreach ($e in $result.Errors) { Write-Host "  ERROR   line $($e.line): $($e.message)" -ForegroundColor Red }
    foreach ($w in $result.Warnings) { Write-Host "  WARNING line $($w.line): $($w.message)" -ForegroundColor Yellow }
}

$output | ConvertTo-Json -Depth 6 -Compress

if ($result.Valid) { exit 0 } else { exit 1 }
