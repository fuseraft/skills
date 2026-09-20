<#
.SYNOPSIS
Runs a WIQL query against Azure DevOps work items through REST.

.PARAMETER Wiql
WIQL query text to execute (required).

.PARAMETER Top
Maximum number of work item references to request (default 50).

.PARAMETER TimePrecision
Enable timePrecision for WIQL execution.

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest. Only REST is implemented.

.PARAMETER Output
Output format: json, table, or tsv.

.PARAMETER Verbose
Also fetches Id, type, title, state and assignee for every returned work item.

.EXAMPLE
pwsh -File scripts/work-item-query.ps1 -Wiql "SELECT [System.Id] FROM WorkItems WHERE [System.State] = 'Active'" -Top 20 -Verbose
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [string]$Wiql,
    [int]$Top = 50,
    [switch]$TimePrecision
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Wiql'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$context = Resolve-AdoContext -Org $Org -Project $Project
$availability = Get-AdoBackendAvailability -Context $context

try {
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'This script currently supports only the REST backend') }

    $payload = New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $Backend -Detail:$detail
    $payload['backend']['resolved'] = $resolvedBackend

    $projectName = Assert-AdoContextValue -Context $context -Key 'project' -Description 'project name'
    $timePrecisionValue = $null
    if ($TimePrecision) { $timePrecisionValue = 'true' }
    $wiqlResponse = Invoke-AdoRest -Context $context -Method POST -Path '_apis/wit/wiql' -Project $projectName `
        -Query ([ordered]@{ '$top' = $Top; timePrecision = $timePrecisionValue }) `
        -Body ([ordered]@{ query = $Wiql })

    $data = $wiqlResponse['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $ids = New-Object System.Collections.Generic.List[object]
    $references = Get-AdoItem $data 'workItems'
    foreach ($item in @($references)) {
        $workItemId = Get-AdoItem $item 'id'
        if ($workItemId -is [int] -or $workItemId -is [long]) { $ids.Add($workItemId) }
    }

    $result = [ordered]@{
        operation      = 'work-item-query'
        query          = [ordered]@{ wiql = $Wiql; top = $Top; time_precision = [bool]$TimePrecision }
        count          = $ids.Count
        work_item_ids  = $ids.ToArray()
        wiql_result    = $data
    }

    if ($detail -and $ids.Count -gt 0) {
        $batchFields = @('System.Id', 'System.WorkItemType', 'System.Title', 'System.State', 'System.AssignedTo')
        $batchResponse = Invoke-AdoRest -Context $context -Method GET -Path '_apis/wit/workitems' `
            -Query ([ordered]@{ ids = ($ids -join ','); fields = ($batchFields -join ',') })
        $result['work_items'] = $batchResponse['data']
    }

    $payload['result'] = $result
    Write-AdoOutput -Payload $payload -Format $Output
    exit 0
}
catch {
    if (-not (Test-AdoError $_)) { throw }
    $errorPayload = New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $Backend -Detail:$detail
    $errorPayload['error'] = $_.Exception.Message
    Write-AdoOutput -Payload $errorPayload -Format $Output
    exit 1
}
