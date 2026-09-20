<#
.SYNOPSIS
Lists the comments on an Azure DevOps work item through REST.

.PARAMETER Id
Work item ID (required).

.PARAMETER Top
Maximum number of comments to return.

.PARAMETER Order
Sort comments by creation date: asc or desc.

.PARAMETER ContinuationToken
Continuation token from a previous response, for paging.

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
pwsh -File scripts/work-item-comment-list.ps1 -Id 48520 -Order desc -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [int]$Top,
    [ValidateSet('asc', 'desc')][string]$Order,
    [string]$ContinuationToken
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Id'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

try {
    $context = Resolve-AdoContext -Org $Org -Project $Project
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'work-item-comment-list.ps1 currently supports only the REST backend') }

    $query = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('Top')) { $query['$top'] = $Top }
    if ($PSBoundParameters.ContainsKey('Order')) {
        if ($Order.ToLowerInvariant() -eq 'asc') { $query['order'] = 'createdDate asc' } else { $query['order'] = 'createdDate desc' }
    }
    if ($PSBoundParameters.ContainsKey('ContinuationToken')) { $query['continuationToken'] = $ContinuationToken }

    $response = Invoke-AdoRest -Context $context -Method GET -Project $context['project'] `
        -Path "_apis/wit/workItems/$Id/comments" -Query $query -ApiVersion '7.1-preview.4'

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $comments = Get-AdoItem $data 'comments'
    if ($null -eq $comments) { $comments = @() }
    $payload = [ordered]@{
        operation          = 'work-item-comment-list'
        backend            = $resolvedBackend
        context            = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request            = [ordered]@{ id = $Id }
        total_count        = (Get-AdoItem $data 'totalCount' (@($comments).Count))
        count              = (Get-AdoItem $data 'count' (@($comments).Count))
        continuation_token = (Get-AdoItem $data 'continuationToken')
        comments           = $comments
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
