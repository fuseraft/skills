<#
.SYNOPSIS
Shared helpers for the datamap skill's JSONL/CSV scripts. Dot-source this file;
do not invoke it directly.

.NOTES
Written for Windows PowerShell 5.1 compatibility (also runs under PowerShell 7+):
- No ternary operator, no null-coalescing (?? / ??=), no ConvertFrom-Json -AsHashtable.
- All file I/O goes through .NET encoding classes instead of relying on cmdlet
  encoding defaults, since Out-File/Set-Content defaults differ across PS versions
  and platforms.
- JSONL files are always written UTF-8 without a BOM and with LF line endings,
  regardless of host OS, so the file is byte-stable between a Windows author and
  a Linux/macOS reader (or vice versa).
#>

# Fixed field order. Every datamap JSONL line is an object with exactly these
# ten keys, in this order. Scripts that re-serialize a line always rebuild it
# in this order rather than trusting whatever order ConvertFrom-Json handed back.
$Script:DataMapFields = @(
    'name', 'src_type', 'src_name', 'src_tbl', 'src_col',
    'dst_type', 'dst_name', 'dst_tbl', 'dst_col', 'notes'
)

# Fields that must always hold a non-blank value. Use the sentinel "N/A" (no
# column concept) or "*" (all columns / not statically resolvable) instead of
# an empty string - see references/schema.md.
$Script:DataMapRequiredNonBlankFields = @(
    'name', 'src_type', 'src_name', 'src_tbl', 'src_col',
    'dst_type', 'dst_name', 'dst_tbl', 'dst_col'
)

# Recommended value sets. These are advisory (a line outside this set produces
# a warning, not an error) because the schema is intentionally extensible -
# see references/schema.md for when it's reasonable to go outside these.
$Script:DataMapKnownSrcTypes = @('Database', 'API', 'File')
$Script:DataMapKnownDstTypes = @('Database', 'API', 'File (Disk)', 'File (SFTP)', 'File (SharePoint)', 'Email')

function Write-Utf8NoBomFile {
    <#
    .SYNOPSIS
    Writes $Content to $Path as UTF-8 without a BOM, no trailing newline added
    beyond what $Content already contains.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Read-Utf8FileRaw {
    <#
    .SYNOPSIS
    Reads a file as a single string using UTF-8 (BOM tolerated on read),
    without PowerShell's per-line encoding/newline guessing.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Split-DataMapLines {
    <#
    .SYNOPSIS
    Splits raw JSONL file content into an array of line strings, normalizing
    CRLF to LF first and dropping exactly one trailing empty line (the common
    "file ends with a newline" case). A blank line anywhere else is preserved
    so the validator can flag it as an error.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$RawContent)

    if ($RawContent.Length -eq 0) {
        return @()
    }

    $normalized = $RawContent -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $normalized -split "`n"

    if ($lines.Length -gt 0 -and $lines[$lines.Length - 1] -eq '') {
        $lines = $lines[0..($lines.Length - 2)]
    }

    return , $lines
}

function ConvertTo-DataMapJsonLine {
    <#
    .SYNOPSIS
    Serializes a datamap row (hashtable or PSCustomObject) to a single compact
    JSON line in fixed field order. Throws if a required field is missing.
    #>
    param([Parameter(Mandatory = $true)]$Row)

    $ordered = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($field in $Script:DataMapFields) {
        $value = $null
        if ($Row -is [System.Collections.IDictionary]) {
            if ($Row.Contains($field)) { $value = $Row[$field] }
        }
        else {
            $prop = $Row.PSObject.Properties[$field]
            if ($prop) { $value = $prop.Value }
        }
        if ($null -eq $value) {
            throw "Row is missing required field '$field'."
        }
        $ordered[$field] = [string]$value
    }

    $json = $ordered | ConvertTo-Json -Compress -Depth 4
    # ConvertTo-Json escapes '/' as '\/' by default (valid JSON either way, but
    # ugly for URLs/paths). Safe to undo: it only ever appears as an escape of
    # a literal '/', never inside a longer escape sequence.
    $json = $json -replace '\\/', '/'
    return $json
}

function Test-DataMapLine {
    <#
    .SYNOPSIS
    Validates one raw JSONL line. Returns a hashtable:
      Valid    - [bool]
      Object   - parsed object in fixed field order (or $null if invalid)
      Errors   - array of error message strings (empty if valid)
      Warnings - array of warning message strings (advisory, e.g. unrecognized src_type)
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RawLine,
        [Parameter(Mandatory = $true)][int]$LineNumber
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($RawLine.Trim().Length -eq 0) {
        $errors.Add("line $LineNumber is blank")
        return @{ Valid = $false; Object = $null; Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
    }

    try {
        $parsed = $RawLine | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $errors.Add("line $LineNumber is not valid JSON: $($_.Exception.Message)")
        return @{ Valid = $false; Object = $null; Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
    }

    if ($parsed -is [System.Array] -or ($parsed -isnot [System.Management.Automation.PSCustomObject])) {
        $errors.Add("line $LineNumber is not a JSON object (got $($parsed.GetType().Name))")
        return @{ Valid = $false; Object = $null; Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
    }

    $presentProps = @($parsed.PSObject.Properties | ForEach-Object { $_.Name })

    foreach ($field in $Script:DataMapFields) {
        if ($presentProps -notcontains $field) {
            $errors.Add("line $LineNumber is missing required key '$field'")
        }
    }

    foreach ($prop in $presentProps) {
        if ($Script:DataMapFields -notcontains $prop) {
            $errors.Add("line $LineNumber has unexpected key '$prop' (not part of the datamap schema)")
        }
    }

    if ($errors.Count -gt 0) {
        return @{ Valid = $false; Object = $null; Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
    }

    foreach ($field in $Script:DataMapFields) {
        $value = $parsed.$field
        if ($null -eq $value -or $value -isnot [string]) {
            $errors.Add("line $LineNumber field '$field' must be a string")
            continue
        }
        if ($Script:DataMapRequiredNonBlankFields -contains $field -and $value.Trim().Length -eq 0) {
            $errors.Add("line $LineNumber field '$field' must not be blank (use 'N/A' or '*' instead of empty string)")
        }
    }

    if ($errors.Count -gt 0) {
        return @{ Valid = $false; Object = $null; Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
    }

    if ($Script:DataMapKnownSrcTypes -notcontains $parsed.src_type) {
        $warnings.Add("line $LineNumber src_type '$($parsed.src_type)' is outside the recommended set ($($Script:DataMapKnownSrcTypes -join ', '))")
    }
    if ($Script:DataMapKnownDstTypes -notcontains $parsed.dst_type) {
        $warnings.Add("line $LineNumber dst_type '$($parsed.dst_type)' is outside the recommended set ($($Script:DataMapKnownDstTypes -join ', '))")
    }

    # Rebuild in fixed field order so downstream consumers never depend on the
    # order keys happened to appear in the source JSON text.
    $ordered = New-Object PSObject
    foreach ($field in $Script:DataMapFields) {
        $ordered | Add-Member -MemberType NoteProperty -Name $field -Value $parsed.$field
    }

    return @{ Valid = $true; Object = $ordered; Errors = @(); Warnings = $warnings.ToArray() }
}

function Test-DataMapFile {
    <#
    .SYNOPSIS
    Validates every line of a JSONL file. Returns a hashtable:
      Valid    - [bool] true only if there are zero errors
      LineCount - number of non-blank lines processed
      Errors   - array of { line, message }
      Warnings - array of { line, message }
      Objects  - array of parsed row objects (fixed field order), only if Valid
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            Valid     = $false
            LineCount = 0
            Errors    = @(@{ line = 0; message = "file not found: $Path" })
            Warnings  = @()
            Objects   = @()
        }
    }

    $raw = Read-Utf8FileRaw -Path $Path
    $lines = Split-DataMapLines -RawContent $raw

    $allErrors = New-Object System.Collections.Generic.List[object]
    $allWarnings = New-Object System.Collections.Generic.List[object]
    $objects = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNumber = $i + 1
        $result = Test-DataMapLine -RawLine $lines[$i] -LineNumber $lineNumber

        foreach ($e in $result.Errors) { $allErrors.Add(@{ line = $lineNumber; message = $e }) }
        foreach ($w in $result.Warnings) { $allWarnings.Add(@{ line = $lineNumber; message = $w }) }
        if ($result.Valid) { $objects.Add($result.Object) }
    }

    return @{
        Valid     = ($allErrors.Count -eq 0)
        LineCount = $lines.Length
        Errors    = $allErrors.ToArray()
        Warnings  = $allWarnings.ToArray()
        Objects   = $objects.ToArray()
    }
}

function ConvertTo-DataMapCsvField {
    <#
    .SYNOPSIS
    RFC 4180 field quoting: quote and double-up embedded quotes whenever the
    field contains a comma, double quote, CR, or LF.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value -match '[,"\r\n]') {
        return '"' + ($Value -replace '"', '""') + '"'
    }
    return $Value
}
