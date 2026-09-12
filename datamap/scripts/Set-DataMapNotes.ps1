<#
.SYNOPSIS
Sets the `notes` field on one or more existing lines of a datamap JSONL file
(Pass 2: annotation). Every other field on every other line is left byte-for-byte
untouched.

.DESCRIPTION
Two mutually exclusive modes:

  Single line - -LineNumber (1-based) + -Notes. Optional -ExpectSrcTbl /
                -ExpectDstTbl sanity-check the row you think you're addressing
                before it gets overwritten, since Pass 2 usually iterates many
                lines in a row and an off-by-one is easy to make.

  Batch       - -Updates pointing at a local JSON array file, each element:
                { "line": <int>, "notes": "<string>",
                  "expectSrcTbl": "<optional>", "expectDstTbl": "<optional>" }
                Applied atomically: every update is checked (line in range,
                expect fields match if given, no duplicate line numbers) before
                any of them are written.

.PARAMETER Path
Path to the .jsonl file to update in place.

.EXAMPLE
pwsh -File scripts/Set-DataMapNotes.ps1 -Path ./datamap.jsonl -LineNumber 3 `
  -Notes "Amount truncated to 2 decimal places before insert" -ExpectDstTbl "dbo.OrderExtract"

.EXAMPLE
pwsh -File scripts/Set-DataMapNotes.ps1 -Path ./datamap.jsonl -Updates ./notes-batch.json
#>
[CmdletBinding(DefaultParameterSetName = 'Single')]
param(
    [Parameter(Mandatory = $true)][string]$Path,

    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][int]$LineNumber,
    [Parameter(Mandatory = $true, ParameterSetName = 'Single')][AllowEmptyString()][string]$Notes,
    [Parameter(ParameterSetName = 'Single')][string]$ExpectSrcTbl,
    [Parameter(ParameterSetName = 'Single')][string]$ExpectDstTbl,

    [Parameter(Mandatory = $true, ParameterSetName = 'Batch')][string]$Updates
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DataMap.Common.ps1')

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "file not found: $Path"
    exit 2
}

$raw = Read-Utf8FileRaw -Path $Path
$lines = Split-DataMapLines -RawContent $raw
if ($lines.Length -eq 0) {
    Write-Error "file is empty: $Path"
    exit 2
}

# Build the list of { LineNumber, Notes, ExpectSrcTbl, ExpectDstTbl } to apply.
$edits = New-Object System.Collections.Generic.List[object]

if ($PSCmdlet.ParameterSetName -eq 'Single') {
    $edits.Add([pscustomobject]@{
        LineNumber   = $LineNumber
        Notes        = $Notes
        ExpectSrcTbl = $ExpectSrcTbl
        ExpectDstTbl = $ExpectDstTbl
    })
}
else {
    if (-not (Test-Path -LiteralPath $Updates)) {
        Write-Error "updates file not found: $Updates"
        exit 2
    }
    $updatesRaw = Read-Utf8FileRaw -Path $Updates
    try {
        $parsedUpdates = $updatesRaw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "updates file is not valid JSON: $($_.Exception.Message)"
        exit 2
    }
    # ConvertFrom-Json unwraps a single-element JSON array (and a bare JSON
    # object) into a scalar PSCustomObject - coerce back to an array so a
    # one-update batch file works the same as one with several.
    if ($parsedUpdates -isnot [System.Array]) { $parsedUpdates = @($parsedUpdates) }

    foreach ($u in $parsedUpdates) {
        $lineProp = $u.PSObject.Properties['line']
        $notesProp = $u.PSObject.Properties['notes']
        if (-not $lineProp -or -not $notesProp) {
            Write-Error "each update must have 'line' and 'notes'"
            exit 2
        }
        $expectSrc = $null
        $expectDst = $null
        if ($u.PSObject.Properties['expectSrcTbl']) { $expectSrc = $u.expectSrcTbl }
        if ($u.PSObject.Properties['expectDstTbl']) { $expectDst = $u.expectDstTbl }
        $edits.Add([pscustomobject]@{
            LineNumber   = [int]$u.line
            Notes        = [string]$u.notes
            ExpectSrcTbl = $expectSrc
            ExpectDstTbl = $expectDst
        })
    }
}

# Validate every edit before touching anything (atomic: all-or-nothing).
$seen = New-Object System.Collections.Generic.HashSet[int]
$errors = New-Object System.Collections.Generic.List[string]
$newLineByIndex = @{}

foreach ($edit in $edits) {
    $n = $edit.LineNumber
    if ($n -lt 1 -or $n -gt $lines.Length) {
        $errors.Add("line $n is out of range (file has $($lines.Length) line(s))")
        continue
    }
    if (-not $seen.Add($n)) {
        $errors.Add("line $n targeted by more than one update in the same batch")
        continue
    }

    $check = Test-DataMapLine -RawLine $lines[$n - 1] -LineNumber $n
    if (-not $check.Valid) {
        $errors.Add("line $n is not currently a valid datamap row, refusing to edit it: $($check.Errors -join '; ')")
        continue
    }

    if ($edit.ExpectSrcTbl -and $check.Object.src_tbl -ne $edit.ExpectSrcTbl) {
        $errors.Add("line $n src_tbl is '$($check.Object.src_tbl)', expected '$($edit.ExpectSrcTbl)' - refusing to edit, addressing looks wrong")
        continue
    }
    if ($edit.ExpectDstTbl -and $check.Object.dst_tbl -ne $edit.ExpectDstTbl) {
        $errors.Add("line $n dst_tbl is '$($check.Object.dst_tbl)', expected '$($edit.ExpectDstTbl)' - refusing to edit, addressing looks wrong")
        continue
    }

    $check.Object.notes = $edit.Notes
    $newLineByIndex[$n - 1] = ConvertTo-DataMapJsonLine -Row $check.Object
}

if ($errors.Count -gt 0) {
    Write-Host "Rejected: $($errors.Count) update(s) failed. Nothing was changed." -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
    exit 1
}

foreach ($index in $newLineByIndex.Keys) {
    $lines[$index] = $newLineByIndex[$index]
}

$newContent = ($lines -join "`n") + "`n"
Write-Utf8NoBomFile -Path $Path -Content $newContent

Write-Host "Updated notes on $($edits.Count) line(s) in $Path." -ForegroundColor Green
exit 0
