-- Time the five UDFs. Assumes lineitem is loaded and analytics.sql applied.
CREATE OR REPLACE FUNCTION tpch_notice_time(name text, t0 timestamptz, n bigint)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  ms double precision;
BEGIN
  ms := 1000.0 * EXTRACT(EPOCH FROM (clock_timestamp() - t0));
  RAISE NOTICE '% | n=% | % ms | % us/row',
    rpad(name, 36), n, round(ms::numeric, 1),
    CASE WHEN n > 0 THEN round((1000.0 * ms / n)::numeric, 2) ELSE 0 END;
END$$;

DO $$
DECLARE
  t0 timestamptz;
  n bigint;
  n_line bigint;
BEGIN
  SELECT count(*) INTO n_line FROM lineitem;
  RAISE NOTICE 'lineitem rows = %', n_line;

  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM tpch_interval_schedule(1, 0, 100000) WHERE taken;
  PERFORM tpch_notice_time('interval schedule (sup 1, taken)', t0, n);

  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM tpch_changepoints(1, 8, 80);
  PERFORM tpch_notice_time('binary segmentation (sup 1)', t0, n);

  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM tpch_supplier_kmeans(4, 15);
  PERFORM tpch_notice_time('k-means++ suppliers k=4', t0, n);

  t0 := clock_timestamp();
  BEGIN
    SELECT count(*) INTO n FROM tpch_holt_winters(1, 4, 8);
    PERFORM tpch_notice_time('holt-winters weekly (sup 1)', t0, n);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'holt-winters skipped: %', SQLERRM;
  END;

  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM tpch_late_viterbi(1);
  PERFORM tpch_notice_time('viterbi late regimes (sup 1)', t0, n);
END$$;

SELECT n_packages, n_cached, n_features FROM lisp.image;
