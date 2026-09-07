# Changelog

## 0.1.0

- `LANGUAGE plecl` / `pleclu`: ECL in the backend (PGXS, PostgreSQL 16+).
- Bytecode-compiled bodies, `fn_extra` xmin cache, SRF materialize, nested SPI.
- Schema `lisp` inspector; bundled ASDF 3.3.7; blob/`PLECLSYS1` load.
- SQL suite (types, SPI, SRF, trigger, errors, inspect, blob, window, TPC-H analytics).
- Client ASDF (`dollar-quote`, inspect, pack).
- CI: Lisp on Ubuntu/macOS/Windows; extension Docker + native matrix; tagged release tarballs.
