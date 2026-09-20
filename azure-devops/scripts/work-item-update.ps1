<#
.SYNOPSIS
Updates an Azure DevOps work item through REST using JSON Patch.

.DESCRIPTION
-Description, -AcceptanceCriteria, -ReproSteps and -SystemInfo are HTML rich-text fields in
Azure DevOps, where a literal newline renders as nothing. Pass plain text with real blank
lines between paragraphs and "- " / "* " for bullet lines; it is converted to <p>/<br>/<ul>
HTML before sending. Text that already contains "<" is sent unchanged.

.PARAMETER Id
Work item ID (required).

.PARAMETER Title
System.Title.

.PARAMETER State
System.State.

.PARAMETER AssignedTo
System.AssignedTo.

.PARAMETER Description
System.Description.

.PARAMETER AcceptanceCriteria
Microsoft.VSTS.Common.AcceptanceCriteria (commonly used on User Story/PBI items).

.PARAMETER ReproSteps
Microsoft.VSTS.TCM.ReproSteps (commonly used on Bug items).

.PARAMETER SystemInfo
Microsoft.VSTS.TCM.SystemInfo (commonly used on Bug items).

.PARAMETER Field
Arbitrary field assignments as NAME=VALUE, for example Microsoft.VSTS.Common.Priority=1.
Pass several as a comma-separated list: -Field A=1,B=2. (Under `pwsh -File` the list arrives as
one string; it is split only when every piece looks like NAME=VALUE, so a value that contains
", then ..." stays intact.)

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest. Only REST is implemented.

.PARAMETER Output
Output format: json, table, or tsv.

.PARAMETER Verbose
Adds request detail and a masked PAT preview to the output.

.EXAMPLE
pwsh -File scripts/work-item-update.ps1 -Id 48520 -State Active -AssignedTo "user@example.com" -Field Microsoft.VSTS.Common.Priority=1

.EXAMPLE
pwsh -File scripts/work-item-update.ps1 -Id 48521 -ReproSteps "1. Do X 2. Observe Y" -SystemInfo "Windows Server 2022, build 20348"
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [string]$Title,
    [string]$State,
    [string]$AssignedTo,
    [string]$Description,
    [string]$AcceptanceCriteria,
    [string]$ReproSteps,
    [string]$SystemInfo,
    [string[]]$Field
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Id'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$returnFields = @(
    'System.WorkItemType', 'System.Title', 'System.State', 'System.AssignedTo',
    'System.Description', 'Microsoft.VSTS.Common.AcceptanceCriteria',
    'Microsoft.VSTS.TCM.ReproSteps', 'Microsoft.VSTS.TCM.SystemInfo'
)

function ConvertFrom-FieldAssignment {
    param([string]$Raw)
    $index = $Raw.IndexOf('=')
    if ($index -lt 0) { throw (New-AdoError ("Invalid -Field value '" + $Raw + "'; expected NAME=VALUE")) }
    $name = $Raw.Substring(0, $index).Trim()
    if ($name.Length -eq 0) { throw (New-AdoError ("Invalid -Field value '" + $Raw + "'; field name cannot be empty")) }
    return [pscustomobject]@{ Name = $name; Value = $Raw.Substring($index + 1) }
}

try {
    $context = Resolve-AdoContext -Org $Org -Project $Project
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'work-item-update.ps1 currently supports only the REST backend') }

    # An unbound [string[]] arrives as a single empty string, so only expand it when it was actually passed.
    $assignments = @()
    if ($PSBoundParameters.ContainsKey('Field')) { $assignments = Expand-AdoFieldArgument -Values $Field }
    $operations = New-Object System.Collections.Generic.List[object]
    $changes = [ordered]@{}

    # name -> [reference name, is HTML rich text], in the order the patch document is built
    $updates = @(
        @('Title', 'System.Title', $false),
        @('State', 'System.State', $false),
        @('AssignedTo', 'System.AssignedTo', $false),
        @('Description', 'System.Description', $true),
        @('AcceptanceCriteria', 'Microsoft.VSTS.Common.AcceptanceCriteria', $true),
        @('ReproSteps', 'Microsoft.VSTS.TCM.ReproSteps', $true),
        @('SystemInfo', 'Microsoft.VSTS.TCM.SystemInfo', $true)
    )
    foreach ($update in $updates) {
        if (-not $PSBoundParameters.ContainsKey($update[0])) { continue }
        $value = $PSBoundParameters[$update[0]]
        if ($update[2]) { $value = ConvertTo-AdoHtml -Text $value }
        $operations.Add([ordered]@{ op = 'add'; path = '/fields/' + $update[1]; value = $value })
        $changes[$update[1]] = $value
    }
    foreach ($raw in $assignments) {
        $parsed = ConvertFrom-FieldAssignment -Raw $raw
        $operations.Add([ordered]@{ op = 'add'; path = '/fields/' + $parsed.Name; value = $parsed.Value })
        $changes[$parsed.Name] = $parsed.Value
    }
    if ($operations.Count -eq 0) {
        throw (New-AdoError 'Specify at least one update via -Title, -State, -AssignedTo, -Description, -AcceptanceCriteria, -ReproSteps, -SystemInfo, or -Field')
    }

    $response = Invoke-AdoRest -Context $context -Method PATCH -Path "_apis/wit/workitems/$Id" `
        -Query ([ordered]@{ fields = ($returnFields -join ',') }) `
        -Body $operations.ToArray() -BodyContentType 'application/json-patch+json'

    $workItem = $response['data']
    if ($null -eq $workItem) { $workItem = [ordered]@{} }
    $fields = Get-AdoItem $workItem 'fields'
    if ($null -eq $fields) { $fields = [ordered]@{} }
    $payload = [ordered]@{
        operation = 'work-item-update'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request   = [ordered]@{
            id      = (Get-AdoItem $workItem 'id')
            changes = $changes
        }
        work_item = [ordered]@{
            id      = (Get-AdoItem $workItem 'id')
            rev     = (Get-AdoItem $workItem 'rev')
            url     = (Get-AdoItem $workItem 'url')
            fields  = $fields
            summary = [ordered]@{
                type        = (Get-AdoItem $fields 'System.WorkItemType')
                title       = (Get-AdoItem $fields 'System.Title')
                state       = (Get-AdoItem $fields 'System.State')
                assigned_to = (Get-AdoItem $fields 'System.AssignedTo')
            }
        }
    }
    if ($detail) { $payload['rest'] = [ordered]@{ status_code = $response['status_code']; url = $response['url'] } }

    Write-AdoOutput -Payload $payload -Format $Output
    exit 0
}
catch {
    if (-not (Test-AdoError $_)) { throw }
    Write-AdoOutput -Payload ([ordered]@{ error = $_.Exception.Message }) -Format $Output
    exit 1
}
