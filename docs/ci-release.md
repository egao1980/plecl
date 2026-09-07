# CI and release

Owning repo: [`egao1980/plecl`](https://github.com/egao1980/plecl). Workflows are `.github/workflows/` in **this** tree. Canned Lisp CI is `egao1980/cl-repository` — no copied `ci-*.lisp`. Workspace checkout is a sibling via `repos.manifest` (`./scripts/bootstrap.sh`).

## Test (`test.yml`)

| job | runner | what |
|---|---|---|
| `lisp` | ubuntu + macOS + windows | `test-system.yml@main` — ASDF `plecl/tests` (Rove) |
| `extension-docker` | ubuntu | `docker build` + full SQL suite |
| `extension` | ubuntu, macOS, windows | native PGXS / MinGW build, `scripts/run-sql-tests.sh`, pack artifact |
| `extension-windows-msvc` | windows-latest | VS 2022 + ECL 24.5.10 + EDB 16.15 zip |

Windows ships **two** ABIs. `windows-x86_64` is MSYS2 MinGW64. `windows-x86_64-msvc` is Visual Studio / EDB. See [install.md](install.md).

## Release (`release.yml`)

Triggers: tag `v*` or `workflow_dispatch`.

1. Same native matrix as `extension`, plus `extension-windows-msvc`: build, SQL suite, `scripts/pack-release.sh`.
2. `publish-source.yml@main` → `ghcr.io/egao1980/cl-systems/plecl:$version` (client ASDF).
3. GitHub Release with `plecl-$version-{linux-x86_64,macos-arm64,windows-x86_64,windows-x86_64-msvc}.{tar.gz,zip}`.

```bash
git tag v0.1.0
git push origin v0.1.0
# or
gh workflow run release.yml -R egao1980/plecl -f version=0.1.0
```

Client-only republish:

```bash
gh workflow run publish-checkout.yml -R egao1980/plecl -f version=0.1.0
```

Packager image: `ghcr.io/egao1980/cl-repository/cl-repository-packager:latest`.

## Local

```bash
make && make install
./scripts/run-sql-tests.sh
./scripts/pack-release.sh linux-x86_64   # or macos-arm64 / windows-x86_64 / windows-x86_64-msvc
```

`DESTDIR` install; the script flattens PGXS paths into `dist/plecl-$version-$platform/`.

## Version

Single source: `plecl.control` `default_version` and `plecl.asd` `:version` — keep them equal. Tag `v$version`.
