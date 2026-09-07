SET statement_timeout = '60s';

CREATE EXTENSION IF NOT EXISTS plecl;

-- scalars
CREATE FUNCTION plecl_add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(1+ n)
$plecl$;

SELECT plecl_add1(41) AS add1;

CREATE FUNCTION plecl_greet(name text) RETURNS text
LANGUAGE plecl STRICT AS $plecl$
(concatenate 'string "hello " name)
$plecl$;

SELECT plecl_greet('world') AS greet;

CREATE FUNCTION plecl_not(x boolean) RETURNS boolean
LANGUAGE plecl STRICT AS $plecl$
(not x)
$plecl$;

SELECT plecl_not(true) AS not_true;
SELECT plecl_not(false) AS not_false;

CREATE FUNCTION plecl_nullif_zero(n integer) RETURNS integer
LANGUAGE plecl AS $plecl$
(if (or (plecl:sql-null-p n) (zerop n)) plecl:+null+ n)
$plecl$;

SELECT plecl_nullif_zero(0) IS NULL AS zero_is_null;
SELECT plecl_nullif_zero(7) AS seven;

-- bigint / float / bytea
CREATE FUNCTION plecl_dbl(x double precision) RETURNS double precision
LANGUAGE plecl STRICT AS $plecl$
(* x 2.0d0)
$plecl$;

SELECT plecl_dbl(1.5) AS dbl;

CREATE FUNCTION plecl_byte_len(b bytea) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(length b)
$plecl$;

SELECT plecl_byte_len('\x00ff'::bytea) AS blen;

-- arrays
CREATE FUNCTION plecl_sum_arr(xs integer[]) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(reduce #'+ xs :initial-value 0)
$plecl$;

SELECT plecl_sum_arr(ARRAY[1,2,3,4]) AS sarr;

CREATE FUNCTION plecl_mkarr(n integer) RETURNS integer[]
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n collect i)
$plecl$;

SELECT plecl_mkarr(3) AS mkarr;

-- SPI
CREATE TABLE plecl_t(id integer PRIMARY KEY, n integer);
INSERT INTO plecl_t VALUES (1, 10), (2, 20);

CREATE FUNCTION plecl_sum_n() RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT COALESCE(SUM(n),0)::int FROM plecl_t")
$plecl$;

SELECT plecl_sum_n() AS sum_n;

CREATE FUNCTION plecl_bump(id integer, by integer) RETURNS integer
LANGUAGE plecl AS $plecl$
(progn
  (plecl:execute "UPDATE plecl_t SET n = n + $1 WHERE id = $2" by id)
  (plecl:query-value "SELECT n FROM plecl_t WHERE id = $1" id))
$plecl$;

SELECT plecl_bump(1, 5) AS bumped;

-- SRF
CREATE FUNCTION plecl_series(n integer) RETURNS SETOF integer
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n collect i)
$plecl$;

SELECT * FROM plecl_series(3) AS s;

-- DO
DO LANGUAGE plecl $plecl$
(plecl:execute "INSERT INTO plecl_t(id, n) VALUES (3, 30)")
$plecl$;

SELECT n FROM plecl_t WHERE id = 3;

-- trigger
CREATE FUNCTION plecl_tg_double() RETURNS trigger
LANGUAGE plecl AS $plecl$
(let ((new (copy-list (plecl:trigger-new))))
  (setf (cdr (assoc :n new)) (* 2 (cdr (assoc :n new))))
  new)
$plecl$;

CREATE TRIGGER plecl_tg
  BEFORE INSERT ON plecl_t
  FOR EACH ROW
  EXECUTE FUNCTION plecl_tg_double();

INSERT INTO plecl_t VALUES (4, 11);
SELECT n FROM plecl_t WHERE id = 4;

-- error surfaces as SQLSTATE
CREATE FUNCTION plecl_boom() RETURNS integer
LANGUAGE plecl AS $plecl$
(error "boom")
$plecl$;

DO $$
BEGIN
  PERFORM plecl_boom();
  RAISE EXCEPTION 'should have failed';
EXCEPTION
  WHEN external_routine_exception THEN
    NULL;
END$$;

-- inspector catalog (schema lisp)
SELECT name FROM lisp.packages WHERE name IN ('PLECL', 'PLECL.USER', 'COMMON-LISP')
ORDER BY 1;

SELECT name FROM lisp.symbols
 WHERE package = 'PLECL' AND name IN ('+NULL+', 'QUERY', 'INSPECT-REF')
ORDER BY 1;

SELECT implementation, n_packages > 0 AS has_packages
  FROM lisp.image;

SELECT count(*) > 0 AS has_ecl
  FROM lisp.features
 WHERE feature IN ('ECL', 'COMMON-LISP');

SELECT path, kind FROM lisp.inspect('(cons 1 2)', 2)
ORDER BY path;
