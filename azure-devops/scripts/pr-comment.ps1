<#
.SYNOPSIS
Adds a comment thread to an Azure DevOps pull request through REST.

.PARAMETER Id
Pull request ID (required).

.PARAMETER Comment
Comment text to add (required).

.PARAMETER Status
Initial thread status: active (default), closed, fixed, wontFix, byDesign, or pending.

.PARAMETER CommentType
Comment type sent to Azure DevOps: text (default) or codeChange.

.PARAMETER FilePath
Optional repository-relative file path for a file-scoped thread.

.PARAMETER RightFileStartLine
Optional 1-based start line for the right file context.

.PARAMETER RightFileStartOffset
1-based start column for the right file context (default 1).

.PARAMETER RightFileEndLine
Optional 1-based end line for the right file context.

.PARAMETER RightFileEndOffset
1-based end column for the right file context (default 1).

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
pwsh -File scripts/pr-comment.ps1 -Repo MyRepo -Id 123 -Comment "Please add a null check here."
#>
[CmdletBinding()]
param(
    [string]$Org,
    [string]$Project,
    [string]$Repo,
    [ValidateSet('auto', 'cli', 'rest')][string]$Backend = 'auto',
    [ValidateSet('json', 'table', 'tsv')][string]$Output = 'json',
    [int]$Id,
    [string]$Comment,
    [ValidateSet('active', 'closed', 'fixed', 'wontFix', 'byDesign', 'pending')][string]$Status = 'active',
    [ValidateSet('text', 'codeChange')][string]$CommentType = 'text',
    [string]$FilePath,
    [int]$RightFileStartLine,
    [int]$RightFileStartOffset = 1,
    [int]$RightFileEndLine,
    [int]$RightFileEndOffset = 1
)

$ErrorActionPreference = 'Stop'
$detail = ($VerbosePreference -eq 'Continue')
$VerbosePreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_ado_common.ps1')

Assert-AdoRequiredParameter -Bound $PSBoundParameters -Name 'Id', 'Comment'
$Backend = $Backend.ToLowerInvariant()
$Output = $Output.ToLowerInvariant()
$Status = Resolve-AdoChoice -Value $Status -Choices @('active', 'closed', 'fixed', 'wontFix', 'byDesign', 'pending')
$CommentType = Resolve-AdoChoice -Value $CommentType -Choices @('text', 'codeChange')

try {
    $hasStart = $PSBoundParameters.ContainsKey('RightFileStartLine')
    $hasEnd = $PSBoundParameters.ContainsKey('RightFileEndLine')
    $hasFile = Test-AdoValue $FilePath

    if (($hasStart -or $hasEnd) -and -not $hasFile) {
        throw (New-AdoError '-FilePath is required when specifying line-based thread context')
    }
    if (-not ($hasFile -and -not $hasStart -and -not $hasEnd)) {
        if (-not $hasStart -or -not $hasEnd) {
            throw (New-AdoError 'Both -RightFileStartLine and -RightFileEndLine are required together')
        }
        if ($RightFileStartLine -lt 1 -or $RightFileEndLine -lt 1) { throw (New-AdoError 'Line numbers must be 1 or greater') }
        if ($RightFileStartOffset -lt 1 -or $RightFileEndOffset -lt 1) { throw (New-AdoError 'Column offsets must be 1 or greater') }
        if ($RightFileEndLine -lt $RightFileStartLine) { throw (New-AdoError 'End line cannot be less than start line') }
        if ($RightFileEndLine -eq $RightFileStartLine -and $RightFileEndOffset -lt $RightFileStartOffset) {
            throw (New-AdoError 'End column cannot be less than start column on the same line')
        }
    }

    $context = Resolve-AdoContext -Org $Org -Project $Project -Repo $Repo -IncludeRepo
    $repoName = Assert-AdoContextValue -Context $context -Key 'repo' -Description 'repository name'
    $availability = Get-AdoBackendAvailability -Context $context
    $resolvedBackend = Resolve-AdoBackend -Requested $Backend -Availability $availability
    if ($resolvedBackend -ne 'rest') { throw (New-AdoError 'pr-comment.ps1 currently supports only the REST backend') }

    $requestBody = [ordered]@{
        status   = $Status
        comments = @([ordered]@{ parentCommentId = 0; content = $Comment; commentType = $CommentType })
    }
    if ($hasFile) {
        if (-not $hasStart -and -not $hasEnd) {
            $requestBody['threadContext'] = [ordered]@{ filePath = $FilePath }
        }
        else {
            $requestBody['threadContext'] = [ordered]@{
                filePath       = $FilePath
                rightFileStart = [ordered]@{ line = $RightFileStartLine; offset = $RightFileStartOffset }
                rightFileEnd   = [ordered]@{ line = $RightFileEndLine; offset = $RightFileEndOffset }
            }
        }
    }

    $response = Invoke-AdoRest -Context $context -Method POST -Project $context['project'] `
        -Path ('_apis/git/repositories/' + (ConvertTo-AdoQuote -Text $repoName) + '/pullRequests/' + $Id + '/threads') `
        -Body $requestBody

    $thread = $response['data']
    if ($null -eq $thread) { $thread = [ordered]@{} }
    $payload = [ordered]@{
        operation = 'pr-comment'
        backend   = $resolvedBackend
        context   = (New-AdoContextPayload -Context $context -Availability $availability -RequestedBackend $resolvedBackend -IncludeRepo -Detail:$detail)
        request   = [ordered]@{ repo = $repoName; id = $Id; thread = $requestBody }
        thread    = $thread
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
