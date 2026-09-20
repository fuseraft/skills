<#
.SYNOPSIS
Gets Azure DevOps pull request details by ID through REST.

.PARAMETER Id
Pull request ID (required).

.PARAMETER IncludeThreads
Include pull request discussion threads.

.PARAMETER IncludeWorkItemRefs
Include linked work item references.

.PARAMETER TopThreads
Maximum number of threads to request when -IncludeThreads is used (default 100).

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
Adds a masked PAT preview plus CLI and extension detail to the output.

.EXAMPLE
pwsh -File scripts/pr-get.ps1 -Repo MyRepo -Id 123 -IncludeThreads -IncludeWorkItemRefs
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [string]$Repo,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [switch]$IncludeThreads,
    [switch]$IncludeWorkItemRefs,
    [int]$TopThreads = 100
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Id'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$context = Resolve-AdoContext -Org $Org -Project $Project -Repo $Repo -IncludeRepo
$availability = Get-AdoBackendAvailability -Context $context

try {
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'This script currently supports only the REST backend') }

    $payload = New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $Backend -IncludeRepo -Detail:$detail
    $payload['backend']['resolved'] = $resolvedBackend

    $repoName = Assert-AdoContextValue -Context $context -Key 'repo' -Description 'repository name'
    $pullRequestPath = '_apis/git/repositories/' + (ConvertTo-AdoQuote -Text $repoName) + '/pullRequests/' + $Id

    $pullRequest = Invoke-AdoRest -Context $context -Method GET -Path $pullRequestPath
    $result = [ordered]@{
        operation         = 'pr-get'
        repo              = $repoName
        pull_request_id   = $Id
        pull_request      = $pullRequest['data']
    }
    if ($IncludeThreads) {
        $threads = Invoke-AdoRest -Context $context -Method GET -Path ($pullRequestPath + '/threads') -Query ([ordered]@{ '$top' = $TopThreads })
        $result['threads'] = $threads['data']
    }
    if ($IncludeWorkItemRefs) {
        $refs = Invoke-AdoRest -Context $context -Method GET -Path ($pullRequestPath + '/workitems')
        $result['work_item_refs'] = $refs['data']
    }

    $payload['result'] = $result
    Write-AdoOutput -Payload $payload -Format $Output
    exit 0
}
catch {
    if (-not (Test-AdoError $_)) { throw }
    $errorPayload = New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $Backend -IncludeRepo -Detail:$detail
    $errorPayload['error'] = $_.Exception.Message
    Write-AdoOutput -Payload $errorPayload -Format $Output
    exit 1
}
