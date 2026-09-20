<#
.SYNOPSIS
Searches code across Azure DevOps Git repositories through the Search REST API.

.DESCRIPTION
Requires the Code Search extension/feature to be enabled for the organization or collection.
On Azure DevOps Services (cloud) the search API is hosted on a dedicated almsearch.dev.azure.com
host; on Azure DevOps Server / on-prem collections it is exposed on the same collection URL used
for every other REST call in this skill.

.PARAMETER Text
Search text or query, for example "ext:cs myFunction" (required).

.PARAMETER Repo
Limit results to one or more repository names. Comma-separated: -Repo A,B.

.PARAMETER Path
Limit results to one or more repository-relative path prefixes. Comma-separated.

.PARAMETER Branch
Limit results to one or more branch names. Comma-separated.

.PARAMETER Extension
Limit results to one or more file extensions, for example cs,py. Comma-separated.

.PARAMETER Top
Maximum number of results to return (default 25).

.PARAMETER Skip
Number of results to skip (default 0).

.PARAMETER IncludeFacets
Include facet counts (repository, project, path, and so on) in the response.

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest. Only REST is implemented.

.PARAMETER Output
Output format: json, table, or tsv.

.PARAMETER Verbose
Adds request detail, the raw search response, and a masked PAT preview to the output.

.EXAMPLE
pwsh -File scripts/code-search.ps1 -Text "ext:cs myFunction" -Repo MyRepo -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [string]$Text,
    [string[]]$Repo,
    [string[]]$Path,
    [string[]]$Branch,
    [string[]]$Extension,
    [int]$Top = 25,
    [int]$Skip = 0,
    [switch]$IncludeFacets
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Text'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$context = Resolve-AdoContext -Org $Org -Project $Project

try {
    $projectName = Assert-AdoContextValue -Context $context -Key 'project' -Description 'project name'
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'code-search.ps1 currently supports only the REST backend') }

    $filters = [ordered]@{ Project = @($projectName) }
    $repos = Expand-AdoListArgument -Values $Repo
    $paths = Expand-AdoListArgument -Values $Path
    $branches = Expand-AdoListArgument -Values $Branch
    $extensions = Expand-AdoListArgument -Values $Extension
    if ($repos.Count -gt 0) { $filters['Repository'] = $repos }
    if ($paths.Count -gt 0) { $filters['Path'] = $paths }
    if ($branches.Count -gt 0) { $filters['Branch'] = $branches }
    if ($extensions.Count -gt 0) { $filters['CodeElement'] = $extensions }

    $requestBody = [ordered]@{
        searchText    = $Text
        '$skip'       = $Skip
        '$top'        = $Top
        filters       = $filters
        includeFacets = [bool]$IncludeFacets
    }
    $searchBaseUrl = Get-AdoSearchBaseUrl -Org $context['org']

    try {
        $response = Invoke-AdoRest -Context $context -Method POST -Path '_apis/search/codesearchresults' -Project $projectName `
            -Body $requestBody -ApiVersion '7.1-preview.1' -BaseUrlOverride $searchBaseUrl
    }
    catch {
        if (-not (Test-AdoError $_)) { throw }
        $message = $_.Exception.Message
        if ($message.Contains('TF400813') -or $message.Contains('404') -or $message.ToLowerInvariant().Contains('not found')) {
            throw (New-AdoError ('Code search is unavailable. Confirm the Code Search extension/feature is installed and enabled for this organization or collection. Original error: ' + $message))
        }
        throw
    }

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $found = Get-AdoItem $data 'results' @()
    if ($null -eq $found) { $found = @() }

    $summaries = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($found)) {
        $repository = Get-AdoItem $item 'repository'
        $itemProject = Get-AdoItem $item 'project'
        $versions = Get-AdoItem $item 'versions'
        $branchName = $null
        if ($null -ne $versions -and @($versions).Count -gt 0) { $branchName = Get-AdoItem (@($versions)[0]) 'branchName' }
        $summaries.Add([ordered]@{
                fileName   = (Get-AdoItem $item 'fileName')
                path       = (Get-AdoItem $item 'path')
                repository = (Get-AdoItem $repository 'name')
                project    = (Get-AdoItem $itemProject 'name')
                branch     = $branchName
                contentId  = (Get-AdoItem $item 'contentId')
            })
    }

    $payload = [ordered]@{
        operation = 'code-search'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request   = $requestBody
        count     = (Get-AdoItem $data 'count' (@($found).Count))
        results   = $summaries.ToArray()
    }
    $facets = Get-AdoItem $data 'facets'
    $hasFacets = $false
    if ($facets -is [System.Collections.IDictionary]) { $hasFacets = ($facets.Count -gt 0) }
    elseif ($null -ne $facets) { $hasFacets = (@($facets).Count -gt 0) }
    if ($hasFacets) { $payload['facets'] = $facets }
    if ($detail) {
        $payload['rest'] = [ordered]@{ status_code = $response['status_code']; url = $response['url'] }
        $payload['raw'] = $data
    }

    Write-AdoOutput -Payload $payload -Format $Output
    exit 0
}
catch {
    if (-not (Test-AdoError $_)) { throw }
    Write-AdoOutput -Payload ([ordered]@{ error = $_.Exception.Message }) -Format $Output
    exit 1
}
