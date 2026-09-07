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
