-- Datum↔CL types (postgres src/pl/plpython/sql/plpython_types.sql)

CREATE FUNCTION t_add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (1+ n) $plecl$;
SELECT plecl_expect(t_add1(41) = 42, 'int4 add1');

CREATE FUNCTION t_i2(n smallint) RETURNS smallint
LANGUAGE plecl STRICT AS $plecl$ (+ n 1) $plecl$;
SELECT plecl_expect(t_i2(2::smallint) = 3, 'int2');

CREATE FUNCTION t_i8(n bigint) RETURNS bigint
LANGUAGE plecl STRICT AS $plecl$ (+ n 1) $plecl$;
SELECT plecl_expect(t_i8(9223372036854775806) = 9223372036854775807, 'int8');

CREATE FUNCTION t_f4(x real) RETURNS real
LANGUAGE plecl STRICT AS $plecl$ (* x 2.0) $plecl$;
SELECT plecl_expect(t_f4(1.5::real) = 3.0::real, 'float4');

CREATE FUNCTION t_f8(x double precision) RETURNS double precision
LANGUAGE plecl STRICT AS $plecl$ (* x 2.0d0) $plecl$;
SELECT plecl_expect(abs(t_f8(1.5) - 3.0) < 1e-12, 'float8');

CREATE FUNCTION t_greet(name text) RETURNS text
LANGUAGE plecl STRICT AS $plecl$
(concatenate 'string "hello " name)
$plecl$;
SELECT plecl_expect(t_greet('world') = 'hello world', 'text');
SELECT plecl_expect(t_greet('café') = 'hello café', 'text utf8');

CREATE FUNCTION t_not(x boolean) RETURNS boolean
LANGUAGE plecl STRICT AS $plecl$ (not x) $plecl$;
SELECT plecl_expect(t_not(true) IS FALSE, 'bool not true — NIL must not be an error');
SELECT plecl_expect(t_not(false) IS TRUE, 'bool not false');

CREATE FUNCTION t_nullif_zero(n integer) RETURNS integer
LANGUAGE plecl AS $plecl$
(if (or (plecl:sql-null-p n) (zerop n)) plecl:+null+ n)
$plecl$;
SELECT plecl_expect(t_nullif_zero(0) IS NULL, 'sql null out');
SELECT plecl_expect(t_nullif_zero(7) = 7, 'non-null out');
SELECT plecl_expect(t_nullif_zero(NULL) IS NULL, 'null in (non-STRICT)');
SELECT plecl_expect(t_add1(NULL) IS NULL, 'STRICT skips NULL');

CREATE FUNCTION t_blen(b bytea) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (length b) $plecl$;
SELECT plecl_expect(t_blen('\x00ff'::bytea) = 2, 'bytea length');

CREATE FUNCTION t_echo_bytea(b bytea) RETURNS bytea
LANGUAGE plecl STRICT AS $plecl$ b $plecl$;
SELECT plecl_expect(t_echo_bytea('\xdead'::bytea) = '\xdead'::bytea, 'bytea echo');

CREATE FUNCTION t_sum_arr(xs integer[]) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(reduce #'+ xs :initial-value 0)
$plecl$;
SELECT plecl_expect(t_sum_arr(ARRAY[1,2,3,4]) = 10, 'int[] in');

CREATE FUNCTION t_mkarr(n integer) RETURNS integer[]
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n collect i)
$plecl$;
SELECT plecl_expect(t_mkarr(3) = ARRAY[1,2,3], 'int[] out');

CREATE FUNCTION t_texts(xs text[]) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (length xs) $plecl$;
SELECT plecl_expect(t_texts(ARRAY['a','bb']) = 2, 'text[] in');

CREATE FUNCTION t_mktexts() RETURNS text[]
LANGUAGE plecl AS $plecl$ (list "x" "y") $plecl$;
SELECT plecl_expect(t_mktexts() = ARRAY['x','y'], 'text[] out');

CREATE FUNCTION t_vc(s varchar) RETURNS varchar
LANGUAGE plecl STRICT AS $plecl$
(concatenate 'string s "!")
$plecl$;
SELECT plecl_expect(t_vc('hi') = 'hi!', 'varchar');

CREATE FUNCTION t_oid(o oid) RETURNS oid
LANGUAGE plecl STRICT AS $plecl$ o $plecl$;
SELECT plecl_expect(t_oid('pg_class'::regclass::oid) = 'pg_class'::regclass::oid, 'oid');

CREATE FUNCTION t_void() RETURNS void
LANGUAGE plecl AS $plecl$ nil $plecl$;
SELECT plecl_expect(t_void() IS NULL, 'void is SQL NULL');

-- Fallback types go through PG input/output (plpython_types numeric/date/json).
CREATE FUNCTION t_num_echo(x numeric) RETURNS numeric
LANGUAGE plecl STRICT AS $plecl$ x $plecl$;
SELECT plecl_expect(t_num_echo(1.5) = 1.5, 'numeric echo');

CREATE FUNCTION t_date_echo(d date) RETURNS date
LANGUAGE plecl STRICT AS $plecl$ d $plecl$;
SELECT plecl_expect(t_date_echo('2020-01-02') = DATE '2020-01-02', 'date echo');

CREATE FUNCTION t_json_echo(j json) RETURNS json
LANGUAGE plecl STRICT AS $plecl$ j $plecl$;
SELECT plecl_expect(t_json_echo('{"a":1}'::json)::jsonb = '{"a":1}'::jsonb, 'json echo');

CREATE TYPE t_pair AS (a integer, b text);
CREATE FUNCTION t_pair_a(p t_pair) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(cdr (assoc :a p))
$plecl$;
SELECT plecl_expect(t_pair_a(ROW(7, 'z')::t_pair) = 7, 'composite in');

CREATE FUNCTION t_pair_mk(n integer) RETURNS t_pair
LANGUAGE plecl STRICT AS $plecl$
(list (cons :a n) (cons :b "z"))
$plecl$;
SELECT plecl_expect((t_pair_mk(9)).a = 9 AND (t_pair_mk(9)).b = 'z', 'composite out');
