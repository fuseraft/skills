<#
.SYNOPSIS
Confirm a directory is a .NET project and report the sandbox-test harness commands.

.DESCRIPTION
sandbox-test is .NET-specific. This script checks for .NET project markers and, when
found, returns the scaffold/build/run/cleanup commands and debug idiom needed for the
skill's Steps 2-4. It never identifies any stack other than .NET - a directory with no
.NET markers reports "stack": "unknown".

Usage: pwsh -File detect_stack.ps1 [path]
  path  Directory to scan (default: current working directory)

Output: JSON to stdout with keys:
  stack        "dotnet" or "unknown"
  display      Human-readable name
  markers      List of marker filenames that triggered detection (empty if unknown)
  shell        Shell assumed for command strings ("bash" or "powershell")
  temp_dir     Platform temp directory - use as the parent for the harness directory
  scaffold     Command to initialize the harness project; substitute <name> and <ts>
  build        Build command ("dotnet build"; empty string when unknown)
  run          Run command ("dotnet run"; empty string when unknown)
  cleanup      Command to delete the harness directory; substitute <harness_dir>
  debug_idiom  One-line debug print example using the [DBG] prefix
  error        Present only when unknown - explains no .NET markers were found

.PARAMETER Path
Directory to scan. Defaults to the current directory.
#>
param(
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

$ExactMarkers = @('global.json', 'Directory.Build.props')
$GlobMarkers = @('*.csproj', '*.sln')

function Test-IsWindowsPlatform {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Find-DotnetMarkers {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $found = New-Object System.Collections.Generic.List[string]

    foreach ($name in $ExactMarkers) {
        if (Test-Path -LiteralPath (Join-Path $Directory $name)) {
            $found.Add($name)
        }
    }
    foreach ($pattern in $GlobMarkers) {
        $hits = Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue
        foreach ($hit in $hits) { $found.Add($hit.Name) }
    }

    # Unary comma: without it, a 1-element result collapses to a bare string when
    # returned from a function, breaking the .Length/slice logic below.
    return , $found.ToArray()
}

$resolvedPath = [System.IO.Path]::GetFullPath($Path)
$isWin = Test-IsWindowsPlatform
$temp = [System.IO.Path]::GetTempPath().TrimEnd('/', '\')
$shell = 'bash'
$cleanup = 'rm -rf <harness_dir>'
if ($isWin) {
    $shell = 'powershell'
    $cleanup = 'Remove-Item -Recurse -Force "<harness_dir>"'
}

$markers = Find-DotnetMarkers -Directory $resolvedPath
if ($markers.Length -gt 5) { $markers = $markers[0..4] }

if ($markers.Length -gt 0) {
    $scaffoldUnix = "dotnet new console -o $temp/harness-<name>-<ts> --force"
    $scaffoldWin = "dotnet new console -o '$temp\harness-<name>-<ts>' --force"
    $scaffold = $scaffoldUnix
    if ($isWin) { $scaffold = $scaffoldWin }

    $result = [ordered]@{
        stack       = 'dotnet'
        display     = '.NET (C#)'
        markers     = $markers
        shell       = $shell
        temp_dir    = $temp
        scaffold    = $scaffold
        build       = 'dotnet build'
        run         = 'dotnet run'
        cleanup     = $cleanup
        debug_idiom = 'Console.WriteLine($"[DBG] label={value}");'
    }
}
else {
    $result = [ordered]@{
        stack       = 'unknown'
        display     = 'Unknown'
        markers     = @()
        shell       = $shell
        temp_dir    = $temp
        scaffold    = ''
        build       = ''
        run         = ''
        cleanup     = $cleanup
        debug_idiom = ''
        error       = "No .NET project markers ($($ExactMarkers -join ', '), $($GlobMarkers -join ', ')) found in $resolvedPath. sandbox-test is .NET-specific and does not apply here."
    }
}

$result | ConvertTo-Json -Depth 4
