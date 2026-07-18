$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $scriptDir 'dbconnect.csproj'
$outputDir = Join-Path $scriptDir 'bin'
$connectionsFile = Join-Path $scriptDir 'DB.connections'

if (-not (Test-Path $projectPath)) {
    throw "Project file not found: $projectPath"
}

Write-Host "Publishing self-contained win-x64 executable..."
dotnet publish $projectPath `
    -c Release `
    -r win-x64 `
    --self-contained true `
    /p:PublishSingleFile=true `
    /p:PublishTrimmed=false `
    -o $outputDir

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

# Copy DB.connections to output directory
if (Test-Path $connectionsFile) {
    Write-Host "Copying DB.connections to output directory..."
    Copy-Item $connectionsFile -Destination $outputDir -Force
} else {
    Write-Warning "DB.connections file not found: $connectionsFile"
}

Write-Host "Publish complete: $outputDir"
