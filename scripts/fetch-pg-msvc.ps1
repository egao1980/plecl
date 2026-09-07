# Download official EDB Windows x64 binaries (MSVC / UCRT), same tree as the installer.
# Usage: fetch-pg-msvc.ps1 [-Dest <pgsql-dir>] [-Version 16.15-1]
param(
    [string]$Dest = $(if ($env:PG_MSVC_ROOT) { $env:PG_MSVC_ROOT } else { Join-Path $env:TEMP 'pgsql' }),
    [string]$Version = $(if ($env:PG_MSVC_VERSION) { $env:PG_MSVC_VERSION } else { '16.15-1' })
)

$ErrorActionPreference = 'Stop'
$Dest = [System.IO.Path]::GetFullPath($Dest)
$url = if ($env:PG_MSVC_URL) {
    $env:PG_MSVC_URL
} else {
    "https://get.enterprisedb.com/postgresql/postgresql-$Version-windows-x64-binaries.zip"
}

$pgConfig = Join-Path $Dest 'bin\pg_config.exe'
if (Test-Path $pgConfig) {
    Write-Host "PostgreSQL already at $Dest"
    exit 0
}

$stageParent = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$zip = Join-Path $stageParent "postgresql-$Version-windows-x64-binaries.zip"
if (-not (Test-Path $zip)) {
    Write-Host "downloading $url"
    curl.exe -fsSL -o $zip $url
}

$leaf = Split-Path -Leaf $Dest.TrimEnd('\', '/')
$extractRoot = if ($leaf -eq 'pgsql') {
    Split-Path -Parent $Dest
} else {
    $Dest
}
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
Write-Host "extracting to $extractRoot"
tar.exe -xf $zip -C $extractRoot

if (-not (Test-Path $pgConfig)) {
    $alt = Join-Path $extractRoot 'pgsql\bin\pg_config.exe'
    if (Test-Path $alt) {
        Write-Host "extracted to $(Split-Path (Split-Path $alt))"
        exit 0
    }
    throw "pg_config.exe not found under $Dest after extract"
}

Write-Host "PostgreSQL ready: $Dest"
