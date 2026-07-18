param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DbArgs
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\dbconnect\bin\dbconnect.exe'
$exe = [System.IO.Path]::GetFullPath($exe)

if (-not (Test-Path $exe)) {
    Write-Error "dbconnect executable not found: $exe"
}

& $exe @DbArgs
exit $LASTEXITCODE
