-- Microbench: plecl vs plpgsql. Run via docker/run-bench.sh
SET statement_timeout = '180s';
CREATE EXTENSION IF NOT EXISTS plecl;

CREATE FUNCTION bench_notice(name text, n bigint, t0 timestamptz) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  ms double precision;
BEGIN
  ms := 1000.0 * EXTRACT(EPOCH FROM (clock_timestamp() - t0));
  RAISE NOTICE '% | n=% | % ms | % us/call',
    rpad(name, 28), n, round(ms::numeric, 1),
    CASE WHEN n > 0 THEN round((1000.0 * ms / n)::numeric, 2) ELSE 0 END;
END$$;

CREATE FUNCTION b_add1(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (1+ n) $plecl$;

CREATE FUNCTION b_add1_plpgsql(n integer) RETURNS integer
LANGUAGE plpgsql STRICT AS $$
BEGIN
  RETURN n + 1;
END$$;

CREATE FUNCTION b_greet(name text) RETURNS text
LANGUAGE plecl STRICT AS $plecl$
(concatenate 'string "hi " name)
$plecl$;

CREATE FUNCTION b_sum_n(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n sum i)
$plecl$;

CREATE FUNCTION b_sum_n_plpgsql(n integer) RETURNS integer
LANGUAGE plpgsql STRICT AS $$
DECLARE
  s integer := 0;
  i integer;
BEGIN
  FOR i IN 1..n LOOP
    s := s + i;
  END LOOP;
  RETURN s;
END$$;

CREATE TABLE b_spi(id integer PRIMARY KEY, n integer);
INSERT INTO b_spi SELECT g, g FROM generate_series(1, 200) g;

CREATE FUNCTION b_spi_sum() RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT COALESCE(SUM(n),0)::int FROM b_spi")
$plecl$;

CREATE FUNCTION b_srf(n integer) RETURNS SETOF integer
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n collect i)
$plecl$;

-- warmup (fills function cache / fn_extra)
SELECT b_add1(1), b_add1_plpgsql(1), b_greet('x'), b_sum_n(10), b_spi_sum();
SELECT count(*) FROM b_srf(10);

DO $$
DECLARE
  t0 timestamptz;
  i integer;
  n integer;
  x integer;
  s bigint;
BEGIN
  n := 40000;
  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    x := b_add1(i);
  END LOOP;
  PERFORM bench_notice('plecl add1', n, t0);

  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    x := b_add1_plpgsql(i);
  END LOOP;
  PERFORM bench_notice('plpgsql add1', n, t0);

  n := 15000;
  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    PERFORM b_greet('world');
  END LOOP;
  PERFORM bench_notice('plecl text', n, t0);

  n := 3000;
  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    x := b_sum_n(200);
  END LOOP;
  PERFORM bench_notice('plecl loop sum 1..200', n, t0);

  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    x := b_sum_n_plpgsql(200);
  END LOOP;
  PERFORM bench_notice('plpgsql loop sum 1..200', n, t0);

  n := 800;
  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    x := b_spi_sum();
  END LOOP;
  PERFORM bench_notice('plecl SPI sum 200 rows', n, t0);

  n := 400;
  t0 := clock_timestamp();
  FOR i IN 1..n LOOP
    SELECT count(*) INTO s FROM b_srf(300);
  END LOOP;
  PERFORM bench_notice('plecl SRF 300 rows', n, t0);
END$$;
