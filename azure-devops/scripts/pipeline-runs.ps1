<#
.SYNOPSIS
Lists Azure DevOps pipeline runs through REST.

.PARAMETER PipelineId
Filter by pipeline ID.

.PARAMETER Branch
Filter by branch ref, for example refs/heads/main.

.PARAMETER Result
Filter by run result.

.PARAMETER State
Filter by run state.

.PARAMETER Top
Maximum number of runs to return (default 25).

.PARAMETER ContinuationToken
Continuation token from a previous response.

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
pwsh -File scripts/pipeline-runs.ps1 -PipelineId 12 -Result succeeded -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$PipelineId,
    [string]$Branch,
    [string]$Result,
    [string]$State,
    [int]$Top = 25,
    [string]$ContinuationToken
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

try {
    $context = Resolve-AdoContext -Org $Org -Project $Project
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability -Supported 'rest'
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'pipeline-runs.ps1 currently supports only the REST backend') }

    $query = [ordered]@{
        '$top'            = $Top
        branch            = (Get-AdoBoundValue $PSBoundParameters 'Branch')
        result            = (Get-AdoBoundValue $PSBoundParameters 'Result')
        state             = (Get-AdoBoundValue $PSBoundParameters 'State')
        continuationToken = (Get-AdoBoundValue $PSBoundParameters 'ContinuationToken')
    }
    if ($PSBoundParameters.ContainsKey('PipelineId')) { $query['pipelineIds'] = $PipelineId }

    $response = Invoke-AdoRest -Context $context -Method GET -Path '_apis/pipelines/runs' -Project $context['project'] -Query $query

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $runs = Get-AdoItem $data 'value' @()
    $payload = [ordered]@{
        operation = 'pipeline-runs'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request   = $query
        count     = (Get-AdoItem $data 'count' (@($runs).Count))
        runs      = $runs
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
