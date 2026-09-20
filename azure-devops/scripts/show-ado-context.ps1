<#
.SYNOPSIS
Shows the resolved execution context that the other scripts in this skill will use.

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Repo
Repository name (default: ADO_REPO).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest.

.PARAMETER Output
Output format: json, table, or tsv.

.PARAMETER Verbose
Adds a masked PAT preview plus CLI and extension detail to the output.

.EXAMPLE
pwsh -File scripts/show-ado-context.ps1 -Output json

.EXAMPLE
pwsh -File scripts/show-ado-context.ps1 -Org https://ado.contoso.mil/tfs/DefaultCollection -Project MyProject -Repo MyRepo -Backend auto -Verbose -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [string]$Repo,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json'
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$context = Resolve-AdoContext -Org $Org -Project $Project -Repo $Repo -IncludeRepo
$availability = Get-AdoBackendAvailability -Context $context

$payload = New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $Backend -IncludeRepo -Detail:$detail

try {
    $payload['backend']['resolved'] = Resolve-AdoBackend -Requested $Backend -Availability $availability
}
catch {
    if (-not (Test-AdoError $_)) { throw }
    $payload['error'] = $_.Exception.Message
    Write-AdoOutput -Payload $payload -Format $Output
    exit 1
}

Write-AdoOutput -Payload $payload -Format $Output
exit 0
