<#
.SYNOPSIS
Deletes an Azure DevOps work item through REST.

.DESCRIPTION
By default the item is moved to the project recycle bin and can be restored. Use
this to remove a work item created by mistake (a duplicate, or one created while testing).

.PARAMETER Id
Work item ID (required).

.PARAMETER Destroy
Permanently destroy the work item instead of moving it to the recycle bin.
Irreversible - omit this unless you are certain.

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
pwsh -File scripts/work-item-delete.ps1 -Id 55863
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [switch]$Destroy
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
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'work-item-delete.ps1 currently supports only the REST backend') }

    $query = $null
    if ($Destroy) { $query = [ordered]@{ destroy = 'true' } }
    $response = Invoke-AdoRest -Context $context -Method DELETE -Path "_apis/wit/workitems/$Id" -Project $context['project'] -Query $query

    $data = $response['data']
    if ($null -eq $data) { $data = [ordered]@{} }
    $resource = Get-AdoItem $data 'resource'
    if ($null -eq $resource) { $resource = [ordered]@{} }
    $recycleBinUrl = $null
    if (-not $Destroy) { $recycleBinUrl = Get-AdoItem $data 'url' }

    $payload = [ordered]@{
        operation = 'work-item-delete'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -Detail:$detail)
        request   = [ordered]@{ id = $Id; destroy = [bool]$Destroy }
        work_item = [ordered]@{
            id                    = (Get-AdoItem $data 'id' $Id)
            type                  = (Get-AdoItem $data 'type')
            title                 = (Get-AdoItem $data 'name')
            project               = (Get-AdoItem $data 'project')
            deleted_date          = (Get-AdoItem $data 'deletedDate')
            deleted_by            = (Get-AdoItem $data 'deletedBy')
            permanently_destroyed = [bool]$Destroy
            recycle_bin_url       = $recycleBinUrl
            fields                = (Get-AdoItem $resource 'fields')
        }
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
