<#
.SYNOPSIS
Appends one or more validated rows to a datamap JSONL file (Pass 1: structural
generation, `notes` left blank).

.DESCRIPTION
Two mutually exclusive modes:

  Single row  - pass all nine structural fields as parameters.
  Batch       - pass -FromJson pointing at a local JSON array file, each
                element an object with the same fields (notes optional,
                defaults to "").

Every row is validated (same rules as Test-DataMapJsonl.ps1) before anything
is written. In batch mode this is all-or-nothing: if any row in the array
fails validation, nothing is appended and every error is reported.

.PARAMETER Path
Path to the .jsonl file. Created if it does not exist; appended to if it does.

.PARAMETER FromJson
Batch mode: path to a JSON file containing an array of row objects.

.EXAMPLE
pwsh -File scripts/New-DataMapEntry.ps1 -Path ./datamap.jsonl `
  -Name "OrderService" -SrcType Database -SrcName "OrdersDB" -SrcTbl "dbo.Orders" -SrcCol "CustomerId" `
  -DstType API -DstName "https://api.shipping.example.com" -DstTbl "POST /v1/shipments" -DstCol "N/A"

.EXAMPLE
pwsh -File scripts/New-DataMapEntry.ps1 -Path ./datamap.jsonl -FromJson ./new-rows.json
#>
[CmdletBinding(DefaultParameterSetName = 'Single')]
param(
    [Parameter(Mandatory = $true)][string]$Path,

    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$Name,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$SrcType,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$SrcName,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$SrcTbl,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$SrcCol,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$DstType,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$DstName,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$DstTbl,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][string]$DstCol,
    [Parameter(ParameterSetName = 'Single')][string]$Notes = '',

    [Parameter(Mandatory = $true, ParameterSetName = 'Batch')][string]$FromJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DataMap.Common.ps1')

function New-DataMapRowCandidate {
    param($SourceObject, [int]$Index)

    $get = {
        param($obj, $key, $default)
        $prop = $obj.PSObject.Properties[$key]
        if ($prop -and $null -ne $prop.Value) { return [string]$prop.Value }
        return $default
    }

    $row = [ordered]@{
        name     = (& $get $SourceObject 'name' $null)
        src_type = (& $get $SourceObject 'src_type' $null)
        src_name = (& $get $SourceObject 'src_name' $null)
        src_tbl  = (& $get $SourceObject 'src_tbl' $null)
        src_col  = (& $get $SourceObject 'src_col' $null)
        dst_type = (& $get $SourceObject 'dst_type' $null)
        dst_name = (& $get $SourceObject 'dst_name' $null)
        dst_tbl  = (& $get $SourceObject 'dst_tbl' $null)
        dst_col  = (& $get $SourceObject 'dst_col' $null)
        notes    = (& $get $SourceObject 'notes' '')
    }
    return $row
}

$candidates = New-Object System.Collections.Generic.List[object]

if ($PSCmdlet.ParameterSetName -eq 'Single') {
    $candidates.Add([ordered]@{
        name     = $Name
        src_type = $SrcType
        src_name = $SrcName
        src_tbl  = $SrcTbl
        src_col  = $SrcCol
        dst_type = $DstType
        dst_name = $DstName
        dst_tbl  = $DstTbl
        dst_col  = $DstCol
        notes    = $Notes
    })
}
else {
    if (-not (Test-Path -LiteralPath $FromJson)) {
        Write-Error "batch file not found: $FromJson"
        exit 2
    }
    $raw = Read-Utf8FileRaw -Path $FromJson
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "batch file is not valid JSON: $($_.Exception.Message)"
        exit 2
    }
    # ConvertFrom-Json unwraps a single-element JSON array (and a bare JSON
    # object) into a scalar PSCustomObject rather than a 1-element array -
    # coerce back to an array so a batch file with exactly one row works the
    # same as one with several.
    if ($parsed -isnot [System.Array]) { $parsed = @($parsed) }

    for ($i = 0; $i -lt $parsed.Length; $i++) {
        $candidates.Add((New-DataMapRowCandidate -SourceObject $parsed[$i] -Index $i))
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "Nothing to append: batch file contained zero rows." -ForegroundColor Yellow
    exit 0
}

# Validate every candidate up front (all-or-nothing for batch mode).
$validatedLines = New-Object System.Collections.Generic.List[string]
$allErrors = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $candidates.Count; $i++) {
    $row = $candidates[$i]
    $missing = @()
    foreach ($field in $Script:DataMapFields) {
        if (-not $row.Contains($field) -or $null -eq $row[$field]) { $missing += $field }
    }
    if ($missing.Count -gt 0) {
        $allErrors.Add("row $($i + 1): missing field(s): $($missing -join ', ')")
        continue
    }

    try {
        $jsonLine = ConvertTo-DataMapJsonLine -Row $row
    }
    catch {
        $allErrors.Add("row $($i + 1): $($_.Exception.Message)")
        continue
    }

    # Re-run through the same validator used for existing files, so a hand-fed
    # single row is held to exactly the same bar as one read back from disk.
    $check = Test-DataMapLine -RawLine $jsonLine -LineNumber ($i + 1)
    if (-not $check.Valid) {
        foreach ($e in $check.Errors) { $allErrors.Add("row $($i + 1): $e") }
        continue
    }

    $validatedLines.Add($jsonLine)
}

if ($allErrors.Count -gt 0) {
    Write-Host "Rejected: $($allErrors.Count) row(s) failed validation. Nothing was written." -ForegroundColor Red
    foreach ($e in $allErrors) { Write-Host "  $e" -ForegroundColor Red }
    exit 1
}

$existing = ''
if (Test-Path -LiteralPath $Path) {
    $existing = Read-Utf8FileRaw -Path $Path
    if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
        $existing += "`n"
    }
}

$newContent = $existing + (($validatedLines.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomFile -Path $Path -Content $newContent

$totalLines = (Split-DataMapLines -RawContent (Read-Utf8FileRaw -Path $Path)).Length
Write-Host "Appended $($validatedLines.Count) row(s) to $Path (now $totalLines line(s) total)." -ForegroundColor Green
foreach ($line in $validatedLines) { Write-Host "  $line" }
exit 0
