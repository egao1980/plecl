# plecl

PostgreSQL procedural language: **Embeddable Common Lisp** in the backend.

Untrusted (`CREATE LANGUAGE plecl` / `pleclu`). Functions run as the `postgres` OS user with a full ECL image — FFI, files, `ext:system` are available. This is `plpython3u`, not `plpgsql`.

```sql
CREATE EXTENSION plecl;

CREATE FUNCTION add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(1+ n)
$plecl$;

SELECT add1(41);  -- 42

CREATE FUNCTION bump(id integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(progn
  (plecl:execute "UPDATE t SET n = n + 1 WHERE id = $1" id)
  (plecl:query-value "SELECT n FROM t WHERE id = $1" id))
$plecl$;
```

`sql-query-postgres` emit:

```lisp
(create-function :add1
  :params (list (in :n :integer))
  :returns :integer
  :language :plecl
  :body (list (plecl-body (1+ n))))
```

## Runtime

| Lisp | Meaning |
|------|---------|
| argument names | bound as symbols in `PLECL.USER` (positional `APPLY`) |
| `plecl:+null+` / `sql-null-p` | SQL NULL (not `NIL` — `NIL` is boolean false / empty list) |
| `plecl:query` | `SELECT` → list of alists (`((:col . val) …)`) |
| `plecl:query-value` | first column of first row, or `+null+` |
| `plecl:execute` | DML/DDL → rowcount |
| `plecl:*trigger*` | plist `:tg-op :new :old :tg-name :tg-table :tg-args …` |
| trigger return | `:ok` / `T` keep row; `:skip` / `+null+` skip; alist replace `NEW` |
| SRF | return a list; one element per row |

SPI `$n` placeholders. Lisp `NIL` as a bind arg is boolean false; use `+null+` for SQL NULL.

`DO LANGUAGE plecl $$ … $$` evals forms in `PLECL.USER`.

Bodies are **interpreted** and cached by `(oid . xmin)` — ECL `COMPILE` shells out to gcc and hangs the backend. `CREATE OR REPLACE` invalidates.

## Demo: window aggregate from SQL

Nothing window-specific is in the extension. `examples/window-agg.sql` is a `CREATE FUNCTION ... LANGUAGE plecl` that partitions sales, ranks, running sum, frame average, lag, z-score, share:

```sql
CREATE FUNCTION demo_sales_window(frame_preceding integer DEFAULT 1)
RETURNS SETOF demo_sales_window
LANGUAGE plecl AS $plecl$
;; query demo_sales, group by store, order by day, emit frame metrics
$plecl$;

SELECT * FROM demo_sales_window(1) ORDER BY store, day;
```

## Inspector (schema `lisp`)

The embedded image is a catalog of views (not a PostgreSQL TABLESPACE):

```sql
SELECT * FROM lisp.image;
SELECT name, n_external FROM lisp.packages WHERE name LIKE 'PLECL%';
SELECT name, fboundp FROM lisp.symbols WHERE package = 'PLECL';
SELECT * FROM lisp.functions;
SELECT * FROM lisp.features;
SELECT * FROM lisp.cache;
SELECT path, kind, type, value FROM lisp.inspect('PLECL:+NULL+', 2);
SELECT path, kind, value FROM lisp.inspect('(cons 1 (list 2 3))', 3);
```

`lisp.inspect(ref, depth)` walks a symbol, package, or a `*read-eval*`-nil form. Views re-run the SRF on each query.

## Build

Needs PostgreSQL 16+ (PGXS) and ECL (`ecl-config`).

```bash
make
sudo make install
psql -c 'CREATE EXTENSION plecl'
```

Docker (extension + SQL suite):

```bash
docker build -f docker/Dockerfile -t plecl .
docker run --rm plecl
```

Client helpers (dollar-quote, no backend):

```bash
ros -e '(asdf:test-system "plecl")' -q
```

## Signals / GC

ECL signal traps are off (`ECL_OPT_TRAP_SIG*`). Datums are copied into CL objects; results are `palloc`'d. Do not let Lisp keep pointers into `palloc` memory.

## Layout

| Path | Role |
|------|------|
| `src/*.c` | call / inline / validator handlers, Datum↔CL, SPI |
| `lisp/plecl.lisp` | backend runtime (installed to `$pkglibdir`) |
| `lisp/inspect.lisp` | inspector / catalog used by schema `lisp` |
| `lisp/client.lisp` | `dollar-quote` / `function-sql` |
| `sql/plecl--0.1.0.sql` | `CREATE LANGUAGE` + schema `lisp` views |
| `examples/window-agg.sql` | demo aggregate created from SQL |

## License

MIT
