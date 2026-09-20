<#
.SYNOPSIS
Shared helpers for the azure-devops skill scripts. Dot-source this file; do not
invoke it directly.

.NOTES
Written for Windows PowerShell 5.1 compatibility (also runs under PowerShell 7+):
- No ternary, null-coalescing, or pipeline-chain operators, and no
  ConvertFrom-Json -AsHashtable.
- JSON is parsed and written by the helpers below instead of ConvertFrom-Json /
  ConvertTo-Json: 5.1 caps ConvertFrom-Json at 2 MB, PowerShell 7.0-7.4 turns
  ISO-8601 strings into DateTime, and ConvertTo-Json's indentation and escaping
  differ between versions. The serializer mirrors Python's json.dump(indent=2):
  2-space indent, insertion order preserved, and non-ASCII escaped as \uXXXX so
  output survives any console code page.
- HTTP goes through System.Net.Http.HttpClient so status and body are available
  without version-specific exception handling, and bodies are always sent and
  read as UTF-8.
- This file (like every script here) is pure ASCII: 5.1 reads BOM-less UTF-8
  files as ANSI.
- PSScriptAnalyzer's PSUseCompatibleTypes reports System.Net.Http.* as "not available
  by default" on the 5.1 profiles. That is a known false positive: Initialize-AdoHttp
  loads the assembly with Add-Type, and the types are created by name (New-Object) so
  they resolve at run time, after the load.
#>

$Script:AdoEnvNames = @{ org = 'ADO_URL'; project = 'ADO_PROJECT'; pat = 'ADO_PAT'; repo = 'ADO_REPO' }
$Script:AdoDefaultApiVersion = '7.0'
$Script:AdoHttpReady = $false

# ---- errors ---------------------------------------------------------------

function New-AdoError {
    <# Creates the exception the scripts throw for expected, reportable failures. #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure constructor; changes no system state.')]
    param([Parameter(Mandatory = $true)][string]$Message)
    $ex = New-Object System.InvalidOperationException($Message)
    $ex.Data['AdoScriptError'] = $true
    return $ex
}

function Test-AdoError {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        if ($null -ne $ex.Data -and $ex.Data.Contains('AdoScriptError')) { return $true }
        $ex = $ex.InnerException
    }
    return $false
}

function Test-AdoValue {
    <# True for a non-empty string; mirrors Python truthiness for optional string values. #>
    param($Value)
    return (-not [string]::IsNullOrEmpty([string]$Value))
}

function Assert-AdoRequiredParameter {
    <# Fails like argparse (stderr, exit 2) instead of letting PowerShell prompt for a missing value. #>
    param(
        [Parameter(Mandatory = $true)]$Bound,
        [Parameter(Mandatory = $true)][string[]]$Name
    )
    $missing = @($Name | Where-Object { -not $Bound.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        $flags = ($missing | ForEach-Object { '-' + $_ }) -join ', '
        [Console]::Error.WriteLine('error: the following arguments are required: ' + $flags)
        exit 2
    }
}

function Get-AdoItem {
    <# dict.get(key, default): null-safe lookup that returns arrays intact. #>
    param($Object, [Parameter(Mandatory = $true)][string]$Key, $Default = $null)
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Key)) { return , $Object[$Key] }
    return , $Default
}

function Get-AdoBoundValue {
    <# An unbound [string] parameter is '' in PowerShell, not $null; this returns $null unless the caller actually passed it. #>
    param([Parameter(Mandatory = $true)]$Bound, [Parameter(Mandatory = $true)][string]$Name)
    if ($Bound.ContainsKey($Name)) { return , $Bound[$Name] }
    return $null
}

function Resolve-AdoChoice {
    <# Returns the canonical casing of a ValidateSet value (ValidateSet itself is case-insensitive). #>
    param([string]$Value, [Parameter(Mandatory = $true)][string[]]$Choices)
    foreach ($choice in $Choices) {
        if ($choice -ieq $Value) { return $choice }
    }
    return $Value
}

function Expand-AdoFieldArgument {
    <#
    Under `pwsh -File`, `-Field a=1,b=2` arrives as ONE string. Split it back into
    assignments, but only when every comma-separated piece looks like NAME=VALUE,
    so a value containing ", then ..." is left alone.
    #>
    param([string[]]$Values)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        $parts = $value.Split(',')
        $allAssignments = ($parts.Length -gt 1)
        foreach ($part in $parts) {
            if ($part -notmatch '^\s*[A-Za-z_][A-Za-z0-9_.]*=') { $allAssignments = $false; break }
        }
        if ($allAssignments) {
            foreach ($part in $parts) { $result.Add($part) }
        }
        else {
            $result.Add($value)
        }
    }
    return , $result.ToArray()
}

function Expand-AdoListArgument {
    <# Splits comma-joined values (see Expand-AdoFieldArgument for why) and drops blanks. #>
    param([string[]]$Values)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        foreach ($part in $value.Split(',')) {
            $trimmed = $part.Trim()
            if ($trimmed.Length -gt 0) { $result.Add($trimmed) }
        }
    }
    return , $result.ToArray()
}

# ---- environment and .env -------------------------------------------------

function Get-AdoEnv {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [Environment]::GetEnvironmentVariable($Name)
}

function Import-AdoDotEnv {
    <# Loads KEY=VALUE lines from the first .env found (skill root, then cwd) without overriding real environment variables. #>
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $candidates = @((Join-Path $skillRoot '.env'), (Join-Path (Get-Location).Path '.env'))
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $text = [System.IO.File]::ReadAllText($candidate, [System.Text.Encoding]::UTF8)
        foreach ($rawLine in [regex]::Split($text, "`r`n|`n|`r")) {
            $line = $rawLine.Trim()
            if ($line.Length -eq 0 -or $line.StartsWith('#') -or $line.IndexOf('=') -lt 0) { continue }
            $index = $line.IndexOf('=')
            $key = $line.Substring(0, $index).Trim()
            $value = $line.Substring($index + 1).Trim()
            if ($key.Length -gt 0 -and $null -eq (Get-AdoEnv -Name $key)) {
                [Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
        break
    }
}

Import-AdoDotEnv

# ---- organization URL and context -----------------------------------------

function ConvertTo-AdoOrgUrl {
    param([string]$Org)
    if ([string]::IsNullOrEmpty($Org)) { return $null }
    return $Org.Trim().TrimEnd('/')
}

function ConvertFrom-AdoUrl {
    <# Minimal urlparse equivalent: scheme, netloc, path. #>
    param([string]$Url)
    $m = [regex]::Match($Url, '^(?:([A-Za-z][A-Za-z0-9+.\-]*):)?(?://([^/?#]*))?([^?#]*)')
    return [ordered]@{
        Scheme = $m.Groups[1].Value
        NetLoc = $m.Groups[2].Value
        Path   = $m.Groups[3].Value
    }
}

function Get-AdoOrgInfo {
    <# Classifies an organization or collection URL as cloud, server (on-prem), or unknown. #>
    param([string]$Org)
    $normalized = ConvertTo-AdoOrgUrl -Org $Org
    if ([string]::IsNullOrEmpty($normalized)) {
        return [ordered]@{
            provided   = $false
            normalized = $null
            host       = $null
            scheme     = $null
            path       = $null
            deployment = 'unknown'
            cloud_host = $false
            on_prem    = $false
            valid      = $false
            reason     = 'No Azure DevOps organization or collection URL provided'
        }
    }

    $parsed = ConvertFrom-AdoUrl -Url $normalized
    $hostName = $parsed.NetLoc.ToLowerInvariant()
    $scheme = $parsed.Scheme.ToLowerInvariant()
    $path = $parsed.Path
    if ([string]::IsNullOrEmpty($path)) { $path = '/' }
    $isValid = ($hostName.Length -gt 0) -and ($scheme -eq 'http' -or $scheme -eq 'https')
    $cloudHost = $hostName.EndsWith('dev.azure.com', [StringComparison]::Ordinal) -or $hostName.EndsWith('visualstudio.com', [StringComparison]::Ordinal)
    $onPrem = $isValid -and (-not $cloudHost)
    $deployment = 'unknown'
    if ($cloudHost) { $deployment = 'cloud' }
    elseif ($onPrem) { $deployment = 'server' }
    $reason = $null
    if (-not $isValid) { $reason = 'Organization URL must include http:// or https:// and a host name' }
    $hostValue = $null
    if ($hostName.Length -gt 0) { $hostValue = $hostName }
    $schemeValue = $null
    if ($scheme.Length -gt 0) { $schemeValue = $scheme }

    return [ordered]@{
        provided   = $true
        normalized = $normalized
        host       = $hostValue
        scheme     = $schemeValue
        path       = $path
        deployment = $deployment
        cloud_host = [bool]$cloudHost
        on_prem    = [bool]$onPrem
        valid      = [bool]$isValid
        reason     = $reason
    }
}

function Resolve-AdoContext {
    <# Command-line values win over environment variables. #>
    param([string]$Org, [string]$Project, [string]$Repo, [switch]$IncludeRepo)
    $orgValue = $Org
    if (-not (Test-AdoValue $orgValue)) { $orgValue = Get-AdoEnv -Name $Script:AdoEnvNames.org }
    $projectValue = $Project
    if (-not (Test-AdoValue $projectValue)) { $projectValue = Get-AdoEnv -Name $Script:AdoEnvNames.project }

    $context = [ordered]@{
        org     = (ConvertTo-AdoOrgUrl -Org $orgValue)
        project = $projectValue
        pat     = (Get-AdoEnv -Name $Script:AdoEnvNames.pat)
    }
    if ($IncludeRepo) {
        $repoValue = $Repo
        if (-not (Test-AdoValue $repoValue)) { $repoValue = Get-AdoEnv -Name $Script:AdoEnvNames.repo }
        $context['repo'] = $repoValue
    }
    return $context
}

function Assert-AdoContextValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $value = $null
    if ($Context.Contains($Key)) { $value = $Context[$Key] }
    if (-not (Test-AdoValue $value)) { throw (New-AdoError ('Missing required ' + $Description)) }
    return [string]$value
}

# ---- backend detection -----------------------------------------------------

function Get-AdoCli {
    $command = Get-Command -Name 'az' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    $path = $null
    if ($null -ne $command) { $path = [string]$command.Source }
    return [ordered]@{ installed = ($null -ne $command); path = $path }
}

function Get-AdoExtension {
    <# Conservative: only reports availability if the CLI exists. #>
    $cli = Get-AdoCli
    if ($cli.installed) {
        return [ordered]@{ installed = $null; detail = 'Unverified without invoking az extension list' }
    }
    return [ordered]@{ installed = $false; detail = 'Azure CLI not found; Azure DevOps extension status unknown' }
}

function Get-AdoBackendAvailability {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)
    $cli = Get-AdoCli
    $patPresent = Test-AdoValue $Context['pat']
    $orgInfo = Get-AdoOrgInfo -Org $Context['org']
    $cliMode = [bool]$cli.installed
    $restMode = [bool]($patPresent -and $orgInfo.valid -and (Test-AdoValue $Context['project']))

    $available = New-Object System.Collections.Generic.List[string]
    if ($cliMode) { $available.Add('cli') }
    if ($restMode) { $available.Add('rest') }
    $preferred = $null
    if ($cliMode) { $preferred = 'cli' }
    elseif ($restMode) { $preferred = 'rest' }

    return [ordered]@{
        cli       = $cliMode
        rest      = $restMode
        available = $available.ToArray()
        preferred = $preferred
        org       = $orgInfo
    }
}

function Resolve-AdoBackend {
    <# -Supported lists the backends the calling script implements, so 'auto' never picks one it cannot run. #>
    param(
        [Parameter(Mandatory = $true)][string]$Requested,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Availability,
        [string[]]$Supported
    )
    if ($Requested -eq 'auto') {
        foreach ($candidate in @($Availability['available'])) {
            if ($Supported -contains $candidate) { return [string]$candidate }
        }
        if (-not (Test-AdoValue $Availability['preferred'])) { throw (New-AdoError 'No usable Azure DevOps backend is available') }
        return [string]$Availability['preferred']
    }
    if (-not $Availability[$Requested]) { throw (New-AdoError ("Requested backend '" + $Requested + "' is not available")) }
    return $Requested
}

function Get-AdoMaskedSecret {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $null }
    if ($Value.Length -le 4) { return ('*' * $Value.Length) }
    return $Value.Substring(0, 2) + '***' + $Value.Substring($Value.Length - 2)
}

function New-AdoContextPayload {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure constructor; changes no system state.')]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Availability,
        [Parameter(Mandatory = $true)][string]$RequestedBackend,
        [switch]$IncludeRepo,
        [switch]$Detail
    )
    $payload = [ordered]@{
        org        = $Context['org']
        project    = $Context['project']
        deployment = $Availability['org']
        backend    = [ordered]@{
            requested = $RequestedBackend
            available = $Availability['available']
            preferred = $Availability['preferred']
        }
        auth       = [ordered]@{ pat_present = [bool](Test-AdoValue $Context['pat']) }
    }
    if ($IncludeRepo) { $payload['repo'] = $Context['repo'] }
    if ($Detail) {
        $payload['auth']['pat_preview'] = Get-AdoMaskedSecret -Value $Context['pat']
        $payload['cli'] = Get-AdoCli
        $payload['extension'] = Get-AdoExtension
    }
    return $payload
}

# ---- JSON ------------------------------------------------------------------

function ConvertTo-AdoJsonString {
    param([string]$Value)
    if (-not [regex]::IsMatch($Value, '[^\x20-\x7e]|["\\]')) { return '"' + $Value + '"' }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $ch = $m.Value[0]
        switch ([int]$ch) {
            34 { return '\"' }
            92 { return '\\' }
            10 { return '\n' }
            13 { return '\r' }
            9 { return '\t' }
            8 { return '\b' }
            12 { return '\f' }
            default { return ('\' + 'u' + ([int]$ch).ToString('x4')) }
        }
    }
    return '"' + [regex]::Replace($Value, '[^\x20-\x7e]|["\\]', $evaluator) + '"'
}

function Format-AdoJsonNumber {
    param($Value)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [double] -or $Value -is [single]) {
        if ([double]::IsNaN([double]$Value)) { return 'NaN' }
        if ([double]::IsPositiveInfinity([double]$Value)) { return 'Infinity' }
        if ([double]::IsNegativeInfinity([double]$Value)) { return '-Infinity' }
        $text = ([double]$Value).ToString('R', $culture)
        if ($text -notmatch '[.EeN]') { $text = $text + '.0' }
        return $text.Replace('E+', 'e+').Replace('E-', 'e-')
    }
    return $Value.ToString([string]$null, $culture)
}

function Test-AdoJsonNumber {
    param($Value)
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) { return $true }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) { return $true }
    return ($Value.GetType().FullName -eq 'System.Numerics.BigInteger')
}

function Write-AdoJsonValue {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        $Value,
        [int]$Indent,
        [int]$Level
    )
    if ($null -eq $Value) { [void]$Builder.Append('null'); return }
    if ($Value -is [bool]) {
        if ($Value) { [void]$Builder.Append('true') } else { [void]$Builder.Append('false') }
        return
    }
    if ($Value -is [string] -or $Value -is [char]) { [void]$Builder.Append((ConvertTo-AdoJsonString -Value ([string]$Value))); return }
    if (Test-AdoJsonNumber -Value $Value) { [void]$Builder.Append((Format-AdoJsonNumber -Value $Value)); return }
    if ($Value -is [datetime]) {
        # Only reached when an old PowerShell 7 parsed a date string; reproduces the original form.
        $stamp = $Value.ToString("yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK", [System.Globalization.CultureInfo]::InvariantCulture)
        [void]$Builder.Append((ConvertTo-AdoJsonString -Value $stamp))
        return
    }

    $pairs = $null
    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = @($Value.Keys)
    }
    elseif ($Value.GetType().Name -eq 'PSCustomObject') {
        $dictionary = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $dictionary[$property.Name] = $property.Value }
        Write-AdoJsonValue -Builder $Builder -Value $dictionary -Indent $Indent -Level $Level
        return
    }

    $inner = ''
    $closing = ''
    if ($Indent -gt 0) {
        $inner = "`n" + (' ' * ($Indent * ($Level + 1)))
        $closing = "`n" + (' ' * ($Indent * $Level))
    }
    $separator = ', '
    if ($Indent -gt 0) { $separator = ',' }

    if ($null -ne $pairs) {
        if ($pairs.Count -eq 0) { [void]$Builder.Append('{}'); return }
        [void]$Builder.Append('{')
        for ($i = 0; $i -lt $pairs.Count; $i++) {
            if ($i -gt 0) { [void]$Builder.Append($separator) }
            [void]$Builder.Append($inner)
            [void]$Builder.Append((ConvertTo-AdoJsonString -Value ([string]$pairs[$i])))
            [void]$Builder.Append(': ')
            Write-AdoJsonValue -Builder $Builder -Value $Value[$pairs[$i]] -Indent $Indent -Level ($Level + 1)
        }
        [void]$Builder.Append($closing)
        [void]$Builder.Append('}')
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { [void]$Builder.Append('[]'); return }
        [void]$Builder.Append('[')
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($i -gt 0) { [void]$Builder.Append($separator) }
            [void]$Builder.Append($inner)
            Write-AdoJsonValue -Builder $Builder -Value $items[$i] -Indent $Indent -Level ($Level + 1)
        }
        [void]$Builder.Append($closing)
        [void]$Builder.Append(']')
        return
    }

    [void]$Builder.Append((ConvertTo-AdoJsonString -Value ([string]$Value)))
}

function ConvertTo-AdoJson {
    <# Indent 0 uses Python's compact json.dumps separators (", " and ": "); Indent 2 matches json.dump(indent=2). #>
    param($Value, [int]$Indent = 0)
    $builder = New-Object System.Text.StringBuilder
    Write-AdoJsonValue -Builder $builder -Value $Value -Indent $Indent -Level 0
    return $builder.ToString()
}

function ConvertTo-AdoPlainObject {
    <# Normalizes parser output to ordered dictionaries, object[] arrays and scalars. #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) { $result[[string]$key] = ConvertTo-AdoPlainObject -Value $Value[$key] }
        return $result
    }
    if ($Value.GetType().Name -eq 'PSCustomObject') {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-AdoPlainObject -Value $property.Value }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { $list.Add((ConvertTo-AdoPlainObject -Value $item)) }
        return , $list.ToArray()
    }
    return $Value
}

function ConvertFrom-AdoJson {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $command = Get-Command -Name ConvertFrom-Json -CommandType Cmdlet
        $arguments = @{ InputObject = $Text }
        if ($command.Parameters.ContainsKey('DateKind')) { $arguments['DateKind'] = 'String' }
        if ($command.Parameters.ContainsKey('NoEnumerate')) { $arguments['NoEnumerate'] = $true }
        return , (ConvertTo-AdoPlainObject -Value (ConvertFrom-Json @arguments))
    }
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 1000
    return , (ConvertTo-AdoPlainObject -Value ($serializer.DeserializeObject($Text)))
}

# ---- output ----------------------------------------------------------------

function Add-AdoFlatRow {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Payload,
        [Parameter(Mandatory = $true)]$Rows,
        [string]$Prefix = ''
    )
    foreach ($key in $Payload.Keys) {
        $fullKey = [string]$key
        if ($Prefix.Length -gt 0) { $fullKey = $Prefix + '.' + $key }
        $value = $Payload[$key]
        if ($value -is [System.Collections.IDictionary]) {
            Add-AdoFlatRow -Payload $value -Rows $Rows -Prefix $fullKey
        }
        elseif ($null -ne $value -and $value -isnot [string] -and $value -is [System.Collections.IEnumerable]) {
            $Rows.Add([pscustomobject]@{ Key = $fullKey; Value = (ConvertTo-AdoJson -Value $value) })
        }
        else {
            $text = ''
            if ($null -ne $value) {
                if ($value -is [double] -or $value -is [single]) { $text = Format-AdoJsonNumber -Value $value }
                else { $text = [System.Convert]::ToString($value, [System.Globalization.CultureInfo]::InvariantCulture) }
            }
            $Rows.Add([pscustomobject]@{ Key = $fullKey; Value = $text })
        }
    }
}

function Write-AdoOutput {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$Format
    )
    if ($Format -eq 'json') {
        Write-Output (ConvertTo-AdoJson -Value $Payload -Indent 2)
        return
    }
    $rows = New-Object System.Collections.Generic.List[object]
    Add-AdoFlatRow -Payload $Payload -Rows $rows
    if ($Format -eq 'tsv') {
        foreach ($row in $rows) { Write-Output ($row.Key + "`t" + $row.Value) }
        return
    }
    $width = 3
    if ($rows.Count -gt 0) {
        $width = 0
        foreach ($row in $rows) { if ($row.Key.Length -gt $width) { $width = $row.Key.Length } }
    }
    foreach ($row in $rows) { Write-Output ($row.Key.PadRight($width) + ' : ' + $row.Value) }
}

# ---- text and URL helpers --------------------------------------------------

function ConvertTo-AdoHtmlEscaped {
    <# Same escapes as Python's html.escape(quote=True). #>
    param([string]$Text)
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#x27;')
}

function ConvertTo-AdoHtml {
    <#
    Converts plain text into the minimal HTML Azure DevOps rich-text fields expect
    (System.Description, AcceptanceCriteria, ReproSteps, SystemInfo). A raw newline
    renders as nothing there, so plain text with blank-line paragraphs and "- " / "* "
    bullets would collapse into one run-on block. Text that already contains markup
    (any "<") is returned untouched so intentional HTML is not double-encoded.
    #>
    param([string]$Text)
    if ($null -eq $Text -or $Text.Contains('<')) { return $Text }
    # Blank-line paragraphs must survive Windows (CRLF) and old-Mac (CR) line endings.
    $Text = $Text.Replace("`r`n", "`n").Replace("`r", "`n")

    $lineBreak = "\r\n|[\n\r\v\f\x1c\x1d\x1e\x85" + [char]0x2028 + [char]0x2029 + ']'
    $result = New-Object System.Text.StringBuilder
    $blocks = $Text.Trim().Split([string[]]@("`n`n"), [System.StringSplitOptions]::None)
    foreach ($block in $blocks) {
        if ($block.Trim().Length -eq 0) { continue }
        $bullets = New-Object System.Collections.Generic.List[string]
        $paragraph = New-Object System.Collections.Generic.List[string]
        $parts = New-Object System.Collections.Generic.List[string]

        foreach ($rawLine in [regex]::Split($block, $lineBreak)) {
            $line = $rawLine.Trim()
            if ($line.Length -eq 0) { continue }
            if ($line.StartsWith('- ', [StringComparison]::Ordinal) -or $line.StartsWith('* ', [StringComparison]::Ordinal)) {
                if ($paragraph.Count -gt 0) {
                    $escaped = @($paragraph | ForEach-Object { ConvertTo-AdoHtmlEscaped -Text $_ })
                    $parts.Add('<p>' + ($escaped -join '<br>') + '</p>')
                    $paragraph.Clear()
                }
                $bullets.Add($line.Substring(2).Trim())
            }
            else {
                if ($bullets.Count -gt 0) {
                    $items = @($bullets | ForEach-Object { '<li>' + (ConvertTo-AdoHtmlEscaped -Text $_) + '</li>' })
                    $parts.Add('<ul>' + ($items -join '') + '</ul>')
                    $bullets.Clear()
                }
                $paragraph.Add($line)
            }
        }
        if ($bullets.Count -gt 0) {
            $items = @($bullets | ForEach-Object { '<li>' + (ConvertTo-AdoHtmlEscaped -Text $_) + '</li>' })
            $parts.Add('<ul>' + ($items -join '') + '</ul>')
        }
        if ($paragraph.Count -gt 0) {
            $escaped = @($paragraph | ForEach-Object { ConvertTo-AdoHtmlEscaped -Text $_ })
            $parts.Add('<p>' + ($escaped -join '<br>') + '</p>')
        }
        [void]$result.Append(($parts -join ''))
    }
    return $result.ToString()
}

function ConvertTo-AdoQuote {
    <# Percent-encodes everything but A-Z a-z 0-9 - . _ ~ (Python's quote(safe='')). #>
    param([string]$Text)
    return [System.Uri]::EscapeDataString($Text)
}

function ConvertTo-AdoQuotePlus {
    <# As ConvertTo-AdoQuote but with '+' for spaces (Python's quote_plus, used by urlencode). #>
    param([string]$Text)
    return [System.Uri]::EscapeDataString($Text).Replace('%20', '+')
}

function Get-AdoSearchBaseUrl {
    <#
    Azure DevOps Services hosts Code Search on almsearch.dev.azure.com (organization kept in the
    path). Azure DevOps Server / on-prem collections serve it from the collection URL itself.
    #>
    param([string]$Org)
    $normalized = ConvertTo-AdoOrgUrl -Org $Org
    if ($null -eq $normalized) { $normalized = '' }
    $info = Get-AdoOrgInfo -Org $normalized
    if (-not $info.valid) { return $normalized }
    if ($info.cloud_host) {
        $parsed = ConvertFrom-AdoUrl -Url $normalized
        if ($parsed.NetLoc.ToLowerInvariant().EndsWith('visualstudio.com', [StringComparison]::Ordinal)) {
            $orgName = $parsed.NetLoc.Split('.')[0]
            if ($parsed.Path.Length -gt 0) { $path = '/' + $orgName + $parsed.Path } else { $path = '/' + $orgName }
        }
        else {
            $path = $parsed.Path
        }
        return ($parsed.Scheme.ToLowerInvariant() + '://almsearch.dev.azure.com' + $path).TrimEnd('/')
    }
    return $normalized
}

function New-AdoRestUrl {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure constructor; changes no system state.')]
    param(
        [Parameter(Mandatory = $true)][string]$Org,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Project,
        [System.Collections.IDictionary]$Query,
        [string]$ApiVersion = $Script:AdoDefaultApiVersion
    )
    $base = $Org.TrimEnd('/')
    $relative = $Path.TrimStart('/')
    if (Test-AdoValue $Project) { $relative = (ConvertTo-AdoQuote -Text $Project) + '/' + $relative }

    $pairs = New-Object System.Collections.Generic.List[string]
    $pairs.Add('api-version=' + (ConvertTo-AdoQuotePlus -Text $ApiVersion))
    if ($null -ne $Query) {
        foreach ($key in $Query.Keys) {
            $value = $Query[$key]
            if ($null -eq $value) { continue }
            foreach ($item in @($value)) {
                $text = [System.Convert]::ToString($item, [System.Globalization.CultureInfo]::InvariantCulture)
                $pairs.Add((ConvertTo-AdoQuotePlus -Text ([string]$key)) + '=' + (ConvertTo-AdoQuotePlus -Text $text))
            }
        }
    }
    return $base + '/' + $relative + '?' + ($pairs -join '&')
}

# ---- REST ------------------------------------------------------------------

function Initialize-AdoHttp {
    if ($Script:AdoHttpReady) { return }
    Add-Type -AssemblyName System.Net.Http
    if ($PSVersionTable.PSEdition -ne 'Core') {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    }
    $Script:AdoHttpReady = $true
}

function Get-AdoInnermostMessage {
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)
    $current = $Exception
    while ($null -ne $current.InnerException) { $current = $current.InnerException }
    return $current.Message
}

function Invoke-AdoRest {
    <# Sends one REST call and returns @{ status_code; url; data; headers }. Non-2xx and transport failures throw an Ado error. #>
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Project,
        [System.Collections.IDictionary]$Query,
        $Body,
        [string]$BodyContentType = 'application/json',
        [string]$ApiVersion = $Script:AdoDefaultApiVersion,
        [string]$Accept = 'application/json',
        [string]$BaseUrlOverride
    )
    $org = $BaseUrlOverride
    if (-not (Test-AdoValue $org)) { $org = Assert-AdoContextValue -Context $Context -Key 'org' -Description 'organization or collection URL' }
    $pat = Assert-AdoContextValue -Context $Context -Key 'pat' -Description 'personal access token'
    $url = New-AdoRestUrl -Org $org -Path $Path -Project $Project -Query $Query -ApiVersion $ApiVersion

    Initialize-AdoHttp
    $token = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(':' + $pat))
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method.ToUpperInvariant())), $url)
        [void]$request.Headers.TryAddWithoutValidation('Authorization', 'Basic ' + $token)
        [void]$request.Headers.TryAddWithoutValidation('Accept', $Accept)
        if ($null -ne $Body) {
            if ($Body -is [byte[]]) { $bytes = $Body } else { $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-AdoJson -Value $Body)) }
            $content = New-Object System.Net.Http.ByteArrayContent(, $bytes)
            [void]$content.Headers.TryAddWithoutValidation('Content-Type', $BodyContentType)
            $request.Content = $content
        }

        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $statusCode = [int]$response.StatusCode
            $rawBytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $responseHeaders = [ordered]@{}
            foreach ($header in $response.Headers) { $responseHeaders[$header.Key.ToLowerInvariant()] = ($header.Value -join ', ') }
        }
        catch {
            throw (New-AdoError ('Azure DevOps REST request failed: ' + (Get-AdoInnermostMessage -Exception $_.Exception)))
        }
    }
    finally {
        $client.Dispose()
    }

    $raw = (New-Object System.Text.UTF8Encoding($false)).GetString($rawBytes).TrimStart([char]0xFEFF)

    if ($statusCode -lt 200 -or $statusCode -gt 299) {
        $details = 'None'
        if ($raw.Length -gt 0) {
            try { $details = ConvertTo-AdoJson -Value (ConvertFrom-AdoJson -Text $raw) } catch { $details = $raw }
        }
        throw (New-AdoError ('Azure DevOps REST request failed with status ' + $statusCode + ': ' + $details))
    }

    $data = $null
    if ($raw.Length -gt 0) {
        try { $data = ConvertFrom-AdoJson -Text $raw }
        catch {
            $preview = $raw
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
            throw (New-AdoError ('Azure DevOps REST response (status ' + $statusCode + ') was not valid JSON; check the organization URL and PAT. Response began: ' + $preview))
        }
    }
    return [ordered]@{ status_code = $statusCode; url = $url; data = $data; headers = $responseHeaders }
}
