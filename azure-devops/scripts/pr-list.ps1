<#
.SYNOPSIS
Lists Azure DevOps pull requests for a repository through REST.

.PARAMETER Status
Pull request status filter: all, active (default), completed, or abandoned.

.PARAMETER CreatorId
Filter by creator identity GUID.

.PARAMETER ReviewerId
Filter by reviewer identity GUID.

.PARAMETER SourceBranch
Filter by source branch name.

.PARAMETER TargetBranch
Filter by target branch name.

.PARAMETER Top
Maximum number of pull requests to return (default 25).

.PARAMETER Skip
Number of pull requests to skip (default 0).

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Repo
Repository name (default: ADO_REPO).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest. Only REST is implemented.

.PARAMETER Output
Output format: json, table, or tsv.

.PARAMETER Verbose
Adds request detail and a masked PAT preview to the output.

.EXAMPLE
pwsh -File scripts/pr-list.ps1 -Repo MyRepo -Status completed -Top 10 -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [string]$Repo,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [ValidateSet('all', 'active', 'completed', 'abandoned')][string]$Status = 'active',
    [string]$CreatorId,
    [string]$ReviewerId,
    [string]$SourceBranch,
    [string]$TargetBranch,
    [int]$Top = 25,
    [int]$Skip = 0
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()
$Status = $Status.ToLowerInvariant()

try {
    $context = Resolve-AdoContext -Org $Org -Project $Project -Repo $Repo -IncludeRepo
    if (-not (Test-AdoValue $context['repo'])) { throw (New-AdoError 'Missing required repository name; pass -Repo or set ADO_REPO') }

    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability -Supported 'rest'
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'pr-list.ps1 currently supports only the REST backend') }

    $statusFilter = $Status
    if ($Status -eq 'all') { $statusFilter = $null }
    $query = [ordered]@{
        '$top'                       = $Top
        '$skip'                      = $Skip
        'searchCriteria.status'      = $statusFilter
        'searchCriteria.creatorId'   = (Get-AdoBoundValue $PSBoundParameters 'CreatorId')
        'searchCriteria.reviewerId'  = (Get-AdoBoundValue $PSBoundParameters 'ReviewerId')
        'searchCriteria.sourceRefName' = (Get-AdoBoundValue $PSBoundParameters 'SourceBranch')
        'searchCriteria.targetRefName' = (Get-AdoBoundValue $PSBoundParameters 'TargetBranch')
    }

    $response = Invoke-AdoRest -Context $context -Method GET -Project $context['project'] `
        -Path ('_apis/git/repositories/' + (ConvertTo-AdoQuote -Text $context['repo']) + '/pullrequests') -Query $query

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $pullRequests = Get-AdoItem $data 'value' @()
    $payload = [ordered]@{
        operation     = 'pr-list'
        backend       = $resolvedBackend
        context       = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -IncludeRepo -Detail:$detail)
        request       = $query
        count         = (Get-AdoItem $data 'count' (@($pullRequests).Count))
        pull_requests = $pullRequests
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
