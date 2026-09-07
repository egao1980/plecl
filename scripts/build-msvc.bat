@echo off
REM Compile and install plecl.dll with the same MSVC/UCRT toolchain as EDB Postgres.
REM Usage (x64 Native Tools prompt):
REM   set ECL_PREFIX=C:\ecl-msvc
REM   set PG_CONFIG=C:\pgsql\bin\pg_config.exe
REM   scripts\build-msvc.bat
REM   scripts\build-msvc.bat install
REM DESTDIR=... redirects install into a pack staging tree (lib/ share/ bin/).
setlocal EnableExtensions

cd /d "%~dp0.."

if "%ECL_PREFIX%"=="" (
  echo ECL_PREFIX is required >&2
  exit /b 1
)
if "%PG_CONFIG%"=="" set PG_CONFIG=pg_config

where cl >nul 2>&1
if errorlevel 1 (
  echo cl.exe not on PATH — run from an x64 Native Tools prompt >&2
  exit /b 1
)

for /f "delims=" %%i in ('"%PG_CONFIG%" --includedir') do set "PG_INC=%%i"
for /f "delims=" %%i in ('"%PG_CONFIG%" --includedir-server') do set "PG_INC_SERVER=%%i"
for /f "delims=" %%i in ('"%PG_CONFIG%" --libdir') do set "PG_LIB=%%i"
for /f "delims=" %%i in ('"%PG_CONFIG%" --pkglibdir') do set "PKGLIBDIR=%%i"
for /f "delims=" %%i in ('"%PG_CONFIG%" --sharedir') do set "SHAREDIR=%%i"
for /f "delims=" %%i in ('"%PG_CONFIG%" --bindir') do set "BINDIR=%%i"

if not "%DESTDIR%"=="" (
  set "PKGLIBDIR=%DESTDIR%\lib"
  set "SHAREDIR=%DESTDIR%\share"
  set "BINDIR=%DESTDIR%\bin"
)

echo pg_config: %PG_CONFIG%
echo ECL_PREFIX: %ECL_PREFIX%
echo includedir-server: %PG_INC_SERVER%

nmake /nologo /f win32\nmake.mak ^
  "ECL_PREFIX=%ECL_PREFIX%" ^
  "PG_INC=%PG_INC%" ^
  "PG_INC_SERVER=%PG_INC_SERVER%" ^
  "PG_LIB=%PG_LIB%" ^
  "PKGLIBDIR=%PKGLIBDIR%" ^
  "SHAREDIR=%SHAREDIR%" ^
  "BINDIR=%BINDIR%" ^
  %*
exit /b %ERRORLEVEL%
