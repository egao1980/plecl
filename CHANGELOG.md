# Changelog

## 0.1.0

- `LANGUAGE plecl` / `pleclu`: ECL in the backend (PGXS, PostgreSQL 16+).
- Bytecode-compiled bodies, `fn_extra` xmin cache, SRF materialize, nested SPI.
- Schema `lisp` inspector; bundled ASDF 3.3.7; blob/`PLECLSYS1` load.
- SQL suite (types, SPI, SRF, trigger, errors, inspect, blob, window, TPC-H analytics).
- Client ASDF (`dollar-quote`, inspect, pack).
- CI: Lisp on Ubuntu/macOS/Windows; extension Docker + native matrix; tagged release tarballs.
- Windows MSVC: `win32/nmake.mak` + ECL 24.5.10 against official/EDB Postgres (`windows-x86_64-msvc`).
- Native CI: PGXS flags before `include $(PGXS)`; `push_macro` around `ecl.h` so PG `ERROR` survives; Homebrew `bdw-gc` include; skip PGDG LLVM bitcode; Windows `initdb --username`; packed systems eval `.lisp` (no `asdf:load-system` / `compile-file` in the backend); `lisp.asdf_version` reads the vendor banner; `asdf.fasc` via LOAD-then-compile-file (ECL 26 `#.+max-character-type-index+`); k-means++ seeded (portable LCG 20260907, 8 inits); Ubuntu `postgresql-16`; drop MSYS2 ECL job.
- Install guide: release drop-in + source, both Windows ABIs, verify/uninstall.
