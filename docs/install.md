# Install

PostgreSQL 16+ (server + PGXS) and ECL (`ecl-config`). Superuser-only language.

| | Ubuntu 24.04 | macOS | Windows |
|---|---|---|---|
| compiler | gcc | clang (Xcode) | MinGW64 (MSYS2) |
| ECL | `apt install ecl` | `brew install ecl` | `mingw-w64-x86_64-ecl` |
| PostgreSQL | `postgresql-server-dev-16` | `brew install postgresql@16` | `mingw-w64-x86_64-postgresql` |
| shared object | `plecl.so` | `plecl.so` | `plecl.dll` |
| binary | EDB / apt cluster | Homebrew keg | **MSYS2 Postgres**, not the EDB MSVC installer |

Windows: MinGW `plecl.dll` loads into MinGW PostgreSQL. It will not load into the EnterpriseDB MSVC build.

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

```bash
pacman -S --needed base-devel mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-ecl mingw-w64-x86_64-postgresql
# in a MINGW64 shell
make
make install
psql -c 'CREATE EXTENSION plecl'
```

## Release tarball

CI tags publish `dist/plecl-$VERSION-$PLATFORM.{tar.gz,zip}`:

```
lib/plecl.so          # .dll on Windows
lib/plecl.lisp
lib/inspect.lisp
lib/blob.lisp
lib/asdf.lisp
share/extension/plecl.control
share/extension/plecl--0.1.0.sql
```

Copy `lib/*` into `$(pg_config --pkglibdir)` and `share/extension/*` into `$(pg_config --sharedir)/extension`.

## Client (no backend)

ASDF system `plecl` — dollar-quote, inspector walkers, blob packer. SBCL/Roswell; does not load `vendor/asdf.lisp`.

```bash
ros -e '(asdf:test-system "plecl")' -q
```

OCI: `ghcr.io/egao1980/cl-systems/plecl:0.1.0` via `publish-checkout.yml`.
