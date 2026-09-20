<#
.SYNOPSIS
Checks whether the environment is ready for Azure DevOps CLI and/or REST usage.

.PARAMETER Org
Azure DevOps organization or collection URL (default: ADO_URL).

.PARAMETER Project
Azure DevOps project name (default: ADO_PROJECT).

.PARAMETER Backend
Backend selection mode: auto, cli, or rest.

.PARAMETER Output
Output format: json, table, or tsv.

.EXAMPLE
pwsh -File scripts/check-ado-prereqs.ps1 -Output json

.EXAMPLE
pwsh -File scripts/check-ado-prereqs.ps1 -Org https://ado.contoso.mil/tfs/DefaultCollection -Project MyProject -Backend rest -Output table
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json'
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()

$context = Resolve-AdoContext -Org $Org -Project $Project
$cli = Get-AdoCli
$extension = Get-AdoExtension
$availability = Get-AdoBackendAvailability -Context $context
$orgInfo = Get-AdoOrgInfo -Org $context['org']

$payload = [ordered]@{
    ok        = (@($availability['available']).Count -gt 0)
    context   = [ordered]@{
        org        = $context['org']
        project    = $context['project']
        deployment = $orgInfo
    }
    cli       = $cli
    extension = $extension
    auth      = [ordered]@{ pat_present = [bool](Test-AdoValue $context['pat']) }
    backend   = [ordered]@{
        requested = $Backend
        available = $availability['available']
        preferred = $availability['preferred']
        resolved  = $null
    }
    checks    = [ordered]@{
        org_present     = [bool](Test-AdoValue $context['org'])
        org_url_valid   = $orgInfo['valid']
        project_present = [bool](Test-AdoValue $context['project'])
        pat_present     = [bool](Test-AdoValue $context['pat'])
    }
}

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
