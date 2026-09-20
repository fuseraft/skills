<#
.SYNOPSIS
Lists Azure DevOps Git repositories through REST.

.PARAMETER AllProjects
List repositories across the whole organization or collection instead of one project.

.PARAMETER IncludeLinks
Include the _links block for each repository in the output.

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
pwsh -File scripts/repo-list.ps1 -Output table

.EXAMPLE
pwsh -File scripts/repo-list.ps1 -AllProjects -Output json
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [switch]$AllProjects,
    [switch]$IncludeLinks
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
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'repo-list.ps1 currently supports only the REST backend') }

    $projectName = $null
    if (-not $AllProjects) { $projectName = $context['project'] }
    if (-not $AllProjects -and -not (Test-AdoValue $projectName)) {
        throw (New-AdoError 'Missing required project name; pass -Project, set ADO_PROJECT, or use -AllProjects')
    }

    $response = Invoke-AdoRest -Context $context -Method GET -Path '_apis/git/repositories' -Project $projectName

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $listed = Get-AdoItem $data 'value' @()
    $repositories = New-Object System.Collections.Generic.List[object]
    foreach ($repository in @($listed)) {
        if ($IncludeLinks -or $repository -isnot [System.Collections.IDictionary]) {
            $repositories.Add($repository)
            continue
        }
        $trimmed = [ordered]@{}
        foreach ($key in $repository.Keys) {
            if ($key -ne '_links') { $trimmed[$key] = $repository[$key] }
        }
        $repositories.Add($trimmed)
    }

    $scope = $projectName
    if ($AllProjects) { $scope = 'all-projects' }
    $payload = [ordered]@{
        operation    = 'repo-list'
        backend      = $resolvedBackend
        context      = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request      = [ordered]@{ scope = $scope }
        count        = (Get-AdoItem $data 'count' $repositories.Count)
        repositories = $repositories.ToArray()
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
