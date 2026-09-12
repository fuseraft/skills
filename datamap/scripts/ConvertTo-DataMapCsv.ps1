<#
.SYNOPSIS
Converts a validated datamap JSONL file to CSV deterministically (Pass 4: final
output). Refuses to run if the JSONL doesn't pass validation first.

.DESCRIPTION
Fixed column order (name,src_type,src_name,src_tbl,src_col,dst_type,dst_name,
dst_tbl,dst_col,notes), RFC 4180 quoting, CRLF line endings, UTF-8 with BOM
(so Excel opens non-ASCII content correctly without a manual import step).

Row order matches the JSONL by default. Pass -Sort for a canonical order
(sorted by every field left to right) when you want output that doesn't depend
on discovery order between runs.

.PARAMETER JsonlPath
Input .jsonl file. Must pass validation (see Test-DataMapJsonl.ps1) or the
script exits 1 without writing anything.

.PARAMETER CsvPath
Output .csv file. Overwritten if it exists.

.PARAMETER Sort
Sort rows canonically (name, src_type, src_name, src_tbl, src_col, dst_type,
dst_name, dst_tbl, dst_col) instead of preserving JSONL order.

.PARAMETER SkipValidation
Bypass the pre-conversion validation check. Not recommended - only for
recovering a CSV snapshot of a JSONL you already know is broken.

.EXAMPLE
pwsh -File scripts/ConvertTo-DataMapCsv.ps1 -JsonlPath ./datamap.jsonl -CsvPath ./datamap.csv
#>
param(
    [Parameter(Mandatory = $true)][string]$JsonlPath,
    [Parameter(Mandatory = $true)][string]$CsvPath,
    [switch]$Sort,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DataMap.Common.ps1')

if (-not $SkipValidation) {
    $validation = Test-DataMapFile -Path $JsonlPath
    if (-not $validation.Valid) {
        Write-Host "Refusing to convert: $($validation.Errors.Count) validation error(s) in $JsonlPath" -ForegroundColor Red
        foreach ($e in $validation.Errors) { Write-Host "  ERROR line $($e.line): $($e.message)" -ForegroundColor Red }
        Write-Host "Fix the JSONL (or re-run with -SkipValidation to force) before converting." -ForegroundColor Red
        exit 1
    }
    $rows = $validation.Objects
    foreach ($w in $validation.Warnings) { Write-Host "  WARNING line $($w.line): $($w.message)" -ForegroundColor Yellow }
}
else {
    if (-not (Test-Path -LiteralPath $JsonlPath)) {
        Write-Error "file not found: $JsonlPath"
        exit 2
    }
    $raw = Read-Utf8FileRaw -Path $JsonlPath
    $lines = Split-DataMapLines -RawContent $raw
    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $rows.Add(($lines[$i] | ConvertFrom-Json))
    }
}

if ($Sort) {
    $rows = $rows | Sort-Object -Property name, src_type, src_name, src_tbl, src_col, dst_type, dst_name, dst_tbl, dst_col
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append(($Script:DataMapFields -join ',')).Append("`r`n")

foreach ($row in $rows) {
    $fields = foreach ($f in $Script:DataMapFields) { ConvertTo-DataMapCsvField -Value ([string]$row.$f) }
    [void]$sb.Append(($fields -join ',')).Append("`r`n")
}

$encWithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($CsvPath, $sb.ToString(), $encWithBom)

$rowCount = @($rows).Count
Write-Host "Wrote $rowCount row(s) to $CsvPath" -ForegroundColor Green
exit 0
