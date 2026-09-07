# Language

Untrusted. `LANGUAGE plecl` / `pleclu` — same handler. Runs as the `postgres` OS user with a full ECL image (FFI, files, `ext:system`). This is `plpython3u`, not `plpgsql`.

## Body

Read in `PLECL.USER`. One form or a `progn`. Arguments are interned from `proargnames` (ASCII-uppercased) and `APPLY`'d.

```sql
CREATE FUNCTION add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(1+ n)
$plecl$;
```

Bodies are **bytecode-compiled** (`ext:install-bytecodes-compiler`) and cached by `(oid . xmin)`. Native ECL `COMPILE` forks gcc and hangs the backend — do not call it. `CREATE OR REPLACE` bumps xmin and recompiles.

`DO LANGUAGE plecl $$ … $$` evals in `PLECL.USER` (not cached).

## NULL

`plecl:+null+` is SQL NULL. Lisp `NIL` is boolean false / empty list. Bind args: `NIL` → `false`, `+null+` → SQL NULL.

## SPI

```lisp
(plecl:query "SELECT a, b FROM t WHERE id = $1" id)   ; list of alists
(plecl:query-value "SELECT n FROM t WHERE id = $1" id) ; first col or +null+
(plecl:execute "UPDATE t SET n = n + 1 WHERE id = $1" id)
```

`$n` placeholders. `read_only` is false (DML works). Nested `query` from a `LANGUAGE plecl` function reuses the outer `SPI_connect`.

Alist keys are `KEYWORD`s from attnames (`l_suppkey` → `:L_SUPPKEY`). Prefer SQL aliases: `AS supplier`.

Dates / `numeric` arrive as text unless you `::float8` / `::int` in the query.

## SRF / trigger

SRF: return a list (one element per row). Composite row = alist of attnames. Prefer `SFRM_Materialize` (one Lisp call + tuplestore).

Trigger plist `plecl:*trigger*`: `:tg-op :new :old :tg-name :tg-table :tg-args …`. Return `:ok`/`T` keep; `:skip`/`+null+` skip; alist replace `NEW`.

## Inspector

Schema `lisp` — views, not a TABLESPACE.

```sql
SELECT * FROM lisp.image;
SELECT * FROM lisp.packages;
SELECT * FROM lisp.functions;
SELECT * FROM lisp.cache;
SELECT path, kind, value FROM lisp.inspect('PLECL:+NULL+', 2);
SELECT lisp.asdf_version();   -- 3.3.7
```

`lisp.systems` + `lisp.load_blob` / `load_system` / `store_system` eval source or a `PLECLSYS1` tree. Paths with `..` or absolute names are rejected. ASDF is bundled (`vendor/asdf.lisp`) and loaded lazily.

## Errors

Unhandled conditions → `ereport(ERROR)`. The ECL debugger hook `cl_throw`s `:PLECL-ABORT` (never `ereport` from the hook — that longjmps through ECL and SIGSEGVs). Signal traps are off (`ECL_OPT_TRAP_SIG*`).

## Types

Native: bool, int2/4/8, float4/8, text/varchar, bytea, arrays, composites. Everything else is `output_as_string` in, `input` out. UTF-8 is decoded into ECL character strings (do not feed Ubuntu ECL a raw base-string and walk `ecl_char`).
