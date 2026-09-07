# CI / local: official EDB Postgres zip + ECL 24.5.10 MSVC + plecl.dll.
# Requires cl.exe / nmake on PATH (x64 Native Tools or ilammy/msvc-dev-cmd).
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

if (-not $env:ECL_PREFIX) {
    $env:ECL_PREFIX = if ($env:RUNNER_TEMP) {
        Join-Path $env:RUNNER_TEMP 'ecl-msvc'
    } else {
        Join-Path $Root 'build\ecl-msvc'
    }
}
if (-not $env:PG_MSVC_ROOT) {
    $env:PG_MSVC_ROOT = if ($env:RUNNER_TEMP) {
        Join-Path $env:RUNNER_TEMP 'pgsql'
    } else {
        Join-Path $Root 'build\pgsql'
    }
}

& (Join-Path $PSScriptRoot 'fetch-pg-msvc.ps1') -Dest $env:PG_MSVC_ROOT
cmd.exe /c (Join-Path $PSScriptRoot 'build-ecl-msvc.bat')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:PG_CONFIG = Join-Path $env:PG_MSVC_ROOT 'bin\pg_config.exe'
if (-not (Test-Path $env:PG_CONFIG)) {
    throw "pg_config missing: $($env:PG_CONFIG)"
}

$bin = Join-Path $env:PG_MSVC_ROOT 'bin'
$env:PATH = "$bin;$($env:ECL_PREFIX);$env:PATH"

cmd.exe /c (Join-Path $PSScriptRoot 'build-msvc.bat')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmd.exe /c (Join-Path $PSScriptRoot 'build-msvc.bat install')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$pkglib = (& $env:PG_CONFIG --pkglibdir).Trim()
if ($env:GITHUB_PATH) {
    Add-Content -Path $env:GITHUB_PATH -Value $bin
    Add-Content -Path $env:GITHUB_PATH -Value $env:ECL_PREFIX
}
if ($env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "ECL_PREFIX=$($env:ECL_PREFIX)"
    Add-Content -Path $env:GITHUB_ENV -Value "PG_CONFIG=$($env:PG_CONFIG)"
    Add-Content -Path $env:GITHUB_ENV -Value "PG_MSVC_ROOT=$($env:PG_MSVC_ROOT)"
    Add-Content -Path $env:GITHUB_ENV -Value "ECLDIR=$pkglib/"
}

Write-Host "MSVC plecl installed; pg_config=$($env:PG_CONFIG)"
& $env:PG_CONFIG --version
