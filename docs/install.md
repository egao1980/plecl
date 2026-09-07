# Install

PostgreSQL 16+ (server + headers) and ECL. Superuser-only language.

| | Ubuntu 24.04 | macOS | Windows MinGW | Windows MSVC |
|---|---|---|---|---|
| compiler | gcc | clang (Xcode) | MinGW64 (MSYS2) | **Visual Studio** (`cl`, `/MD`) |
| ECL | `apt install ecl` | `brew install ecl` | `mingw-w64-x86_64-ecl` | **24.5.10 from source** (`scripts/build-ecl-msvc.bat`) |
| PostgreSQL | `postgresql-server-dev-16` | `brew install postgresql@16` | `mingw-w64-x86_64-postgresql` | **EDB / official zip** |
| shared object | `plecl.so` | `plecl.so` | `plecl.dll` | `plecl.dll` + `ecl.dll` |
| loads into | apt / EDB cluster | Homebrew keg | **MSYS2 Postgres only** | **EDB / official installer** |

Two Windows ABIs. Do not load a MinGW `plecl.dll` into EDB `postgres.exe` (or the reverse). ECL 26+ dropped the MSVC port — the official-Windows build pins **24.5.10**.

## Ubuntu

```bash
sudo apt-get install -y build-essential ecl libgc-dev libgmp-dev \
  postgresql postgresql-server-dev-16
make
sudo make install
sudo -u postgres psql -c 'CREATE EXTENSION plecl'
```

Docker (hermetic SQL suite):

```bash
docker build -f docker/Dockerfile -t plecl-test .
docker run --rm plecl-test
```

## macOS

```bash
brew install postgresql@16 ecl
export PATH="$(brew --prefix postgresql@16)/bin:$PATH"
make
make install
psql -c 'CREATE EXTENSION plecl'
```

`postgresql@16` is keg-only. Keep its `bin` on `PATH` so `pg_config` matches the cluster you start.

## Windows (MSYS2 MinGW64)

For MSYS2 PostgreSQL only.

```bash
pacman -S --needed base-devel mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-ecl mingw-w64-x86_64-postgresql
# in a MINGW64 shell
make
make install
psql -c 'CREATE EXTENSION plecl'
```

## Windows (MSVC, official / EDB)

Same compiler as the EnterpriseDB installer: VS 2019/2022 x64, `/MD` UCRT. ECL is built with that toolchain and statically absorbs gc/gmp.

```bat
REM x64 Native Tools Command Prompt for VS 2022
set ECL_PREFIX=C:\ecl-msvc
set PG_CONFIG=C:\Program Files\PostgreSQL\16\bin\pg_config.exe

powershell -File scripts\fetch-pg-msvc.ps1
REM skip fetch if you already have the EDB install; point PG_CONFIG at it

scripts\build-ecl-msvc.bat
scripts\build-msvc.bat
scripts\build-msvc.bat install
```

`install` copies `plecl.dll` + Lisp + `encodings` into `pkglibdir`, and `ecl.dll` into both `pkglibdir` and `bindir` (so `postgres.exe` finds it). `_PG_init` sets `ECLDIR` to `pkglibdir` when unset.

One-shot (CI / local throwaway EDB zip):

```powershell
# from an x64 Native Tools prompt
powershell -File scripts\ci-windows-msvc.ps1
bash scripts/run-sql-tests.sh
```

Pins: ECL **24.5.10**, EDB binaries **16.15-1** (`PG_MSVC_VERSION`, `PG_MSVC_URL` override).

## Release tarball

CI tags publish `dist/plecl-$VERSION-$PLATFORM.{tar.gz,zip}`:

```
lib/plecl.so          # .dll on Windows
lib/ecl.dll           # MSVC zip only
lib/encodings/        # MSVC zip only
lib/plecl.lisp
lib/inspect.lisp
lib/blob.lisp
lib/asdf.lisp
share/extension/plecl.control
share/extension/plecl--0.1.0.sql
```

| artifact | loads into |
|---|---|
| `windows-x86_64` | MSYS2 MinGW64 Postgres |
| `windows-x86_64-msvc` | EDB / official MSVC Postgres |

Copy `lib/*` into `$(pg_config --pkglibdir)` and `share/extension/*` into `$(pg_config --sharedir)/extension`. For MSVC also copy `ecl.dll` into `$(pg_config --bindir)`.

## Client (no backend)

ASDF system `plecl` — dollar-quote, inspector walkers, blob packer. SBCL/Roswell; does not load `vendor/asdf.lisp`.

```bash
ros -e '(asdf:test-system "plecl")' -q
```

OCI: `ghcr.io/egao1980/cl-systems/plecl:0.1.0` via `publish-checkout.yml`.
