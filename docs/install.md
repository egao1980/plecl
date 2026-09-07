# Install

`LANGUAGE plecl` is untrusted and `superuser = true`. The backend process loads a full ECL image (FFI, files, `ext:system`).

PostgreSQL **16** (same major as the artifact; rebuild for 17/18 — `PG_MODULE_MAGIC` is per-major). Superuser session to `CREATE EXTENSION`.

## Which binary

| artifact | compiler | loads into | needs at runtime |
|---|---|---|---|
| `plecl-$V-linux-x86_64.tar.gz` | gcc | apt / PGDG / EDB Linux | `libecl` from the distro |
| `plecl-$V-macos-arm64.tar.gz` | clang | Homebrew `postgresql@16` | `brew install ecl` |
| `plecl-$V-windows-x86_64-msvc.zip` | VS `/MD` | **EDB / official Windows installer** | shipped `ecl.dll` + `encodings/` |

MSYS2 no longer ships `mingw-w64-x86_64-ecl`. Windows CI and the release zip are MSVC / EDB. ECL 26+ dropped the MSVC port — the official-Windows build is **ECL 24.5.10**.

GitHub Release: https://github.com/egao1980/plecl/releases

---

## From a release (no compiler)

### Linux

```bash
# libecl.so.X must already be on the loader path (apt: ecl)
tar -C /tmp -xzf plecl-0.1.0-linux-x86_64.tar.gz
sudo cp /tmp/plecl-0.1.0-linux-x86_64/lib/* "$(pg_config --pkglibdir)/"
sudo cp /tmp/plecl-0.1.0-linux-x86_64/share/extension/* "$(pg_config --sharedir)/extension/"
sudo -u postgres psql -c 'CREATE EXTENSION plecl'
```

`pg_config` must be the cluster you run, not a different major.

### macOS (Homebrew postgresql@16)

```bash
brew install ecl postgresql@16
export PATH="$(brew --prefix postgresql@16)/bin:$PATH"
tar -C /tmp -xzf plecl-0.1.0-macos-arm64.tar.gz
cp /tmp/plecl-0.1.0-macos-arm64/lib/* "$(pg_config --pkglibdir)/"
cp /tmp/plecl-0.1.0-macos-arm64/share/extension/* "$(pg_config --sharedir)/extension/"
psql -d postgres -c 'CREATE EXTENSION plecl'
```

### Windows — official / EDB (MSVC zip)

Admin PowerShell. Adjust `16` if the install is another major you built for.

```powershell
$root = "C:\Program Files\PostgreSQL\16"
$src  = "C:\path\to\plecl-0.1.0-windows-x86_64-msvc"
# zip expands to that directory (lib\ + share\extension\)

Copy-Item -Force "$src\lib\plecl.dll"        "$root\lib\"
Copy-Item -Force "$src\lib\ecl.dll"          "$root\lib\"
Copy-Item -Force "$src\lib\ecl.dll"          "$root\bin\"   # postgres.exe searches bindir
Copy-Item -Force "$src\lib\*.lisp"           "$root\lib\"
if (Test-Path "$src\lib\help.doc") {
  Copy-Item -Force "$src\lib\help.doc"       "$root\lib\"
}
if (Test-Path "$src\lib\encodings") {
  Copy-Item -Recurse -Force "$src\lib\encodings" "$root\lib\encodings"
}
Copy-Item -Force "$src\share\extension\*"    "$root\share\extension\"

Restart-Service postgresql-x64-16   # Services.msc name may be "postgresql-x64-16"
```

Then as a superuser (`postgres` + the password from the EDB installer):

```bat
"C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres -c "CREATE EXTENSION plecl"
```

`ecl.dll` **must** sit next to `postgres.exe` (`bindir`). Putting it only in `lib\` is not enough — Windows does not search the loading DLL’s directory. `_PG_init` sets `ECLDIR` to `pkglibdir` when unset so `encodings\` resolves.

Optional: set a machine env `ECLDIR=C:\Program Files\PostgreSQL\16\lib\` (trailing slash) if you move those files.

---

## From source

### Ubuntu 24.04

```bash
sudo apt-get install -y build-essential ecl libgc-dev libgmp-dev \
  postgresql-16 postgresql-server-dev-16
make with_llvm=no
sudo make with_llvm=no install
sudo -u postgres psql -c 'CREATE EXTENSION plecl'
```

Hermetic SQL suite:

```bash
docker build -f docker/Dockerfile -t plecl-test .
docker run --rm plecl-test
```

### macOS

```bash
brew install postgresql@16 ecl
export PATH="$(brew --prefix postgresql@16)/bin:$PATH"
make
make install
psql -d postgres -c 'CREATE EXTENSION plecl'
```

`postgresql@16` is keg-only — `pg_config` on `PATH` must match the cluster.

### Windows MSVC (existing EDB install)

Prereqs:

- Visual Studio 2019/2022 **x64**, workload “Desktop development with C++” (or Build Tools + MSVC + Windows SDK)
- Official PostgreSQL 16 already installed (`pg_config.exe`, `include\server`, `lib\postgres.lib`)
- curl + tar (Windows 10+), or Git for Windows

Admin **x64 Native Tools Command Prompt**:

```bat
cd /d C:\src\plecl
set ECL_PREFIX=C:\ecl-msvc
set "PG_CONFIG=C:\Program Files\PostgreSQL\16\bin\pg_config.exe"
scripts\build-ecl-msvc.bat
scripts\build-msvc.bat
scripts\build-msvc.bat install
```

`install` writes `plecl.dll`, `*.lisp`, `encodings\`, `help.doc` to `pkglibdir`, `plecl.control` + `plecl--0.1.0.sql` to `share\extension`, and `ecl.dll` to **both** `pkglibdir` and `bindir`.

Restart the PostgreSQL Windows service, then `CREATE EXTENSION plecl`.

ECL 24.5.10 is downloaded to `%TEMP%` / `%RUNNER_TEMP%` and installed to `ECL_PREFIX` (no spaces). First build is slow; rerunning the bat is a no-op if `ecl.dll` is already there.

Throwaway EDB zip + ECL + install (CI):

```powershell
# still from an x64 Native Tools prompt
powershell -File scripts\ci-windows-msvc.ps1
bash scripts/run-sql-tests.sh
```

Pins: ECL **24.5.10**, EDB binaries **16.15-1**. Overrides: `ECL_VERSION`, `ECL_URL`, `ECL_PREFIX`, `PG_MSVC_VERSION`, `PG_MSVC_URL`, `PG_MSVC_ROOT`.

---

## Enable / verify

```sql
CREATE EXTENSION plecl;          -- superuser
CREATE EXTENSION IF NOT EXISTS plecl;

CREATE FUNCTION add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$(1+ n)$plecl$;

SELECT add1(41);                 -- 42
SELECT lisp.asdf_version();      -- 3.3.7
```

`DROP EXTENSION plecl CASCADE;` removes the language, schema `lisp`, and functions that depend on it. It does not delete `plecl.dll` / `ecl.dll`.

SQL suite after a source install: `./scripts/run-sql-tests.sh` (throwaway cluster; Windows uses TCP `127.0.0.1:55432`).

---

## Uninstall (files)

```bash
# Unix
sudo rm -f "$(pg_config --pkglibdir)/plecl.so" \
           "$(pg_config --pkglibdir)/"{plecl,inspect,blob,asdf}.lisp
sudo rm -f "$(pg_config --sharedir)/extension/plecl.control" \
           "$(pg_config --sharedir)/extension/plecl--*.sql"
```

```powershell
$root = "C:\Program Files\PostgreSQL\16"
Remove-Item -Force "$root\lib\plecl.dll", "$root\lib\ecl.dll", "$root\bin\ecl.dll"
Remove-Item -Force "$root\lib\plecl.lisp", "$root\lib\inspect.lisp", "$root\lib\blob.lisp", "$root\lib\asdf.lisp"
Remove-Item -Recurse -Force "$root\lib\encodings" -ErrorAction SilentlyContinue
Remove-Item -Force "$root\share\extension\plecl.control", "$root\share\extension\plecl--0.1.0.sql"
```

---

## Layout of a release dir

```
lib/plecl.so | plecl.dll
lib/ecl.dll            # MSVC zip only
lib/encodings/         # MSVC zip only
lib/help.doc           # MSVC zip only, if present
lib/plecl.lisp
lib/inspect.lisp
lib/blob.lisp
lib/asdf.lisp
share/extension/plecl.control
share/extension/plecl--0.1.0.sql
```

---

## Troubleshooting

| symptom | cause |
|---|---|
| `could not load library … 193` / `%1 is not a valid Win32` | MinGW dll in EDB, or 32-bit vs 64-bit |
| `The specified module could not be found` / `ecl.dll` | `ecl.dll` not in `bindir`; or MinGW `PATH` missing `/mingw64/bin` |
| `incompatible library` / magic number | artifact built for another PG major |
| `plecl: failed to load …/plecl.lisp` | lisp files not in `pkglibdir` |
| missing encodings / unicode errors (MSVC) | `lib\encodings\` not copied; `ECLDIR` not pointing at `pkglibdir` |
| `CREATE EXTENSION` → `not found` | control/sql not in `share/extension`; wrong `pg_config` |
| backend hangs on first call | body used native `COMPILE` (forks gcc). Use bytecode only |
| `permission denied` installing under `Program Files` | need an elevated prompt |

`shared_preload_libraries` is not required. First `LANGUAGE plecl` call runs `cl_boot`.

## Client (no backend)

ASDF system `plecl` — dollar-quote, inspector walkers, blob packer. Does not load `vendor/asdf.lisp`.

```bash
ros -e '(asdf:test-system "plecl")' -q
```

OCI: `ghcr.io/egao1980/cl-systems/plecl:0.1.0`.
