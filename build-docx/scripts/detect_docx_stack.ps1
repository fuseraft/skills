<#
.SYNOPSIS
Detect project stack and available DOCX libraries.

.DESCRIPTION
Usage: pwsh -File detect_docx_stack.ps1 <project-root>
Output: JSON with language, available_libraries, recommended

.PARAMETER ProjectRoot
Directory to scan. Defaults to the current directory.
#>
param(
    [string]$ProjectRoot = '.'
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectRoot)

function Get-ProjectFiles {
    <#
    Iterative (non-recursive-call) directory walk that prunes any directory whose
    full path contains .git, node_modules, bin, or obj - mirrors the reference
    Python implementation's exclusion behavior without the recursion depth limits
    Windows PowerShell 5.1 can hit on deep trees.
    #>
    param([Parameter(Mandatory = $true)][string]$Root)

    $skipTokens = @('.git', 'node_modules', 'bin', 'obj')
    $files = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Root)

    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()

        $skip = $false
        foreach ($token in $skipTokens) {
            if ($dir.Contains($token)) { $skip = $true; break }
        }
        if ($skip) { continue }

        $entries = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                $pending.Push($entry.FullName)
            }
            else {
                $files.Add($entry.FullName)
            }
        }
    }

    # Unary comma: prevents a 1-element result from collapsing to a bare string
    # when this function's output is captured by the caller.
    return , $files.ToArray()
}

function Test-PythonLibrary {
    param([Parameter(Mandatory = $true)][string]$ModuleName)

    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pythonCmd) { $pythonCmd = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $pythonCmd) { return $false }

    & $pythonCmd.Source -c "import $ModuleName" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-NodeLibrary {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Root)
    return (Test-Path -LiteralPath (Join-Path (Join-Path $Root 'node_modules') $Name) -PathType Container)
}

$allFiles = Get-ProjectFiles -Root $root

$fileNamesLower = New-Object System.Collections.Generic.List[string]
foreach ($f in $allFiles) {
    $fileNamesLower.Add([System.IO.Path]::GetFileName($f).ToLowerInvariant())
}
$fileNameSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($n in $fileNamesLower) { [void]$fileNameSet.Add($n) }

$hasCsproj = $false
foreach ($n in $fileNamesLower) {
    if ($n.EndsWith('.csproj') -or $n.EndsWith('.sln')) { $hasCsproj = $true; break }
}
$hasPackageJson = $fileNameSet.Contains('package.json')
$hasPython = ($fileNameSet.Contains('pyproject.toml')) -or ($fileNameSet.Contains('setup.py')) -or ($fileNameSet.Contains('requirements.txt'))
$hasGo = $fileNameSet.Contains('go.mod')

$language = 'unknown'
$available = New-Object System.Collections.Generic.List[string]
$recommended = ''

if ($hasCsproj) {
    $language = 'dotnet'
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($file in $allFiles) {
        if ($file.ToLowerInvariant().EndsWith('.csproj')) {
            $content = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
            if ($content) {
                if ($content.Contains('DocumentFormat.OpenXml')) {
                    if ($seen.Add('DocumentFormat.OpenXml')) { $available.Add('DocumentFormat.OpenXml') }
                }
                if ($content.Contains('DocX')) {
                    if ($seen.Add('DocX')) { $available.Add('DocX') }
                }
            }
        }
    }
    if ($available.Contains('DocX')) { $recommended = 'DocX' } else { $recommended = 'DocumentFormat.OpenXml' }
}
elseif ($hasPackageJson) {
    $language = 'nodejs'
    if (Test-NodeLibrary -Name 'docx' -Root $root) { $available.Add('docx') }
    $recommended = 'docx'
}
elseif ($hasPython) {
    $language = 'python'
    if (Test-PythonLibrary -ModuleName 'docx') { $available.Add('docx') }
    $recommended = 'python-docx'
}
elseif ($hasGo) {
    $language = 'go'
    if (Test-PythonLibrary -ModuleName 'docx') { $available.Add('python-docx (helper script)') }
    $recommended = 'python-docx (helper script)'
}
else {
    if (Test-PythonLibrary -ModuleName 'docx') { $available.Add('python-docx (helper script)') }
    $recommended = 'python-docx (helper script)'
}

$result = [ordered]@{
    language            = $language
    available_libraries = $available.ToArray()
    recommended         = $recommended
}

$result | ConvertTo-Json -Depth 4
