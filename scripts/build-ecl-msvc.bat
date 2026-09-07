@echo off
REM Build ECL 24.5.10 with MSVC (last release with a first-class msvc/ tree).
REM ECL 26+ dropped Visual Studio. Requires x64 Native Tools / vcvars64.
REM Usage: build-ecl-msvc.bat
REM Env: ECL_PREFIX (install dest), ECL_SRC (existing unpacked tree), ECL_VERSION
setlocal EnableExtensions EnableDelayedExpansion

if "%ECL_VERSION%"=="" set ECL_VERSION=24.5.10
if "%ECL_PREFIX%"=="" (
  echo ECL_PREFIX is required >&2
  exit /b 1
)
if "%ECL_URL%"=="" set ECL_URL=https://ecl.common-lisp.dev/static/files/release/ecl-%ECL_VERSION%.tgz

where cl >nul 2>&1
if errorlevel 1 (
  echo cl.exe not on PATH — run from an x64 Native Tools prompt or ilammy/msvc-dev-cmd >&2
  exit /b 1
)
where nmake >nul 2>&1
if errorlevel 1 (
  echo nmake.exe not on PATH >&2
  exit /b 1
)

if exist "%ECL_PREFIX%\ecl.dll" if exist "%ECL_PREFIX%\ecl.lib" (
  echo ECL already installed at %ECL_PREFIX%
  exit /b 0
)

if "%ECL_SRC%"=="" (
  if not "%RUNNER_TEMP%"=="" (
    set "ECL_SRC=%RUNNER_TEMP%\ecl-%ECL_VERSION%"
  ) else (
    set "ECL_SRC=%TEMP%\ecl-%ECL_VERSION%"
  )
)

if not exist "%ECL_SRC%\msvc\Makefile" (
  echo downloading ECL %ECL_VERSION%
  if not "%RUNNER_TEMP%"=="" (
    set "TGZ=%RUNNER_TEMP%\ecl-%ECL_VERSION%.tgz"
    set "PARENT=%RUNNER_TEMP%"
  ) else (
    set "TGZ=%TEMP%\ecl-%ECL_VERSION%.tgz"
    set "PARENT=%TEMP%"
  )
  curl.exe -fsSL -o "!TGZ!" "%ECL_URL%"
  if errorlevel 1 exit /b 1
  if exist "%ECL_SRC%" rmdir /S /Q "%ECL_SRC%"
  tar.exe -xf "!TGZ!" -C "!PARENT!"
  if errorlevel 1 exit /b 1
  if not exist "%ECL_SRC%\msvc\Makefile" (
    echo expected %ECL_SRC%\msvc\Makefile after extract >&2
    exit /b 1
  )
)

echo building ECL %ECL_VERSION% → %ECL_PREFIX%
pushd "%ECL_SRC%\msvc"
nmake /nologo ECL_WIN64=1 GMP_TYPE=gc
if errorlevel 1 (
  popd
  exit /b 1
)
nmake /nologo ECL_WIN64=1 install "prefix=%ECL_PREFIX%"
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if not exist "%ECL_PREFIX%\ecl.dll" (
  echo nmake install did not produce %ECL_PREFIX%\ecl.dll >&2
  exit /b 1
)
echo ECL installed: %ECL_PREFIX%
exit /b 0
