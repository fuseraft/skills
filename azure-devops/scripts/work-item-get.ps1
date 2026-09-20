<#
.SYNOPSIS
Gets an Azure DevOps work item by ID through REST.

.PARAMETER Id
Work item ID (required).

.PARAMETER Fields
Comma-separated field reference names to include, for example System.Id,System.Title,System.State.

.PARAMETER Expand
Expand related work item data: all, fields, links, relations, or none (default).

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
pwsh -File scripts/work-item-get.ps1 -Id 48520 -Fields System.Id,System.Title,System.State
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [string]$Fields,
    [ValidateSet('all', 'fields', 'links', 'relations', 'none')][string]$Expand = 'none'
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Id'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()
$Expand = $Expand.ToLowerInvariant()

try {
    $context = Resolve-AdoContext -Org $Org -Project $Project
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'work-item-get.ps1 currently supports only the REST backend') }

    $fieldList = New-Object System.Collections.Generic.List[string]
    if (Test-AdoValue $Fields) {
        foreach ($field in $Fields.Split(',')) {
            $trimmed = $field.Trim()
            if ($trimmed.Length -gt 0) { $fieldList.Add($trimmed) }
        }
    }
    $query = [ordered]@{}
    if ($fieldList.Count -gt 0) { $query['fields'] = ($fieldList -join ',') }
    if ($Expand -ne 'none') { $query['$expand'] = $Expand }

    $response = Invoke-AdoRest -Context $context -Method GET -Path "_apis/wit/workitems/$Id" -Query $query

    $workItem = $response['data']
    $payload = [ordered]@{
        operation = 'work-item-get'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request   = [ordered]@{
            id     = (Get-AdoItem $workItem 'id')
            fields = $fieldList.ToArray()
            expand = $Expand
        }
        work_item = $workItem
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
