-- Tiny fixture for the TPC-H Lisp UDFs (not the 1GB load).
\ir ../../examples/tpch/schema.sql
TRUNCATE lineitem;

-- Interval: A [1,3] r=10, B [2,4] r=8, C [4,6] r=10 → optimal A+C.
INSERT INTO lineitem VALUES
  (1, 1, 1, 1, 1, 10, 0, 0, 'A', 'O',
   DATE '1992-01-02', DATE '1992-01-01', DATE '1992-01-04', 'NONE', 'AIR', 'A'),
  (1, 1, 1, 2, 1, 8, 0, 0, 'A', 'O',
   DATE '1992-01-03', DATE '1992-01-01', DATE '1992-01-05', 'NONE', 'AIR', 'B'),
  (1, 1, 1, 3, 1, 10, 0, 0, 'A', 'O',
   DATE '1992-01-05', DATE '1992-01-01', DATE '1992-01-07', 'NONE', 'AIR', 'C');

-- Change points + Viterbi: 8 low / 8 high / late streak in the middle of high.
INSERT INTO lineitem
SELECT 10 + g, 1, 2, 1, 1,
       CASE WHEN g <= 8 THEN 10 ELSE 40 END, 0, 0,
       'A', 'O',
       DATE '1992-01-01' + (g - 1),
       DATE '1992-01-01' + (g - 1) - CASE WHEN g BETWEEN 10 AND 13 THEN 10 ELSE 0 END,
       DATE '1992-01-01' + (g - 1) + CASE WHEN g BETWEEN 10 AND 13 THEN 8 ELSE 0 END,
       'NONE', 'AIR', 'cp'
FROM generate_series(1, 16) g;

-- k-means: two blobs on discount/delay.
INSERT INTO lineitem
SELECT 100 + g, 1, 10 + (g % 5), 1, 1, 100, 0.01, 0, 'A', 'O',
       DATE '1992-06-01', DATE '1992-06-01', DATE '1992-06-02',
       'NONE', 'AIR', 'lo'
FROM generate_series(0, 19) g;
INSERT INTO lineitem
SELECT 200 + g, 1, 20 + (g % 5), 1, 1, 100, 0.20, 0, 'R', 'O',
       DATE '1992-06-01', DATE '1992-05-01', DATE '1992-07-01',
       'NONE', 'SHIP', 'hi'
FROM generate_series(0, 19) g;

-- Holt-Winters: 12 weekly points, season 4.
INSERT INTO lineitem
SELECT 300 + g, 1, 3, 1, 1, (10 + (g % 4) * 3 + g * 0.2), 0, 0, 'A', 'O',
       DATE '1995-01-02' + ((g - 1) * 7),
       DATE '1995-01-02' + ((g - 1) * 7),
       DATE '1995-01-04' + ((g - 1) * 7),
       'NONE', 'AIR', 'hw'
FROM generate_series(1, 12) g;

\ir ../../examples/tpch/analytics.sql

SELECT plecl_expect(
  (SELECT count(*) FILTER (WHERE taken) FROM tpch_interval_schedule(1, 0, 100)) = 2,
  'interval: two non-overlapping picks');
SELECT plecl_expect(
  (SELECT coalesce(sum(revenue), 0) FROM tpch_interval_schedule(1, 0, 100) WHERE taken) = 20,
  'interval: A+C revenue 20');
SELECT plecl_expect(
  (SELECT taken FROM tpch_interval_schedule(1, 0, 100) WHERE linenumber = 2) IS NOT TRUE,
  'interval: overlapping B dropped');

SELECT plecl_expect(
  (SELECT count(*) FROM tpch_changepoints(2, 3, 20)) >= 2,
  'changepoints: at least two segments');
SELECT plecl_expect(
  (SELECT max(mean_rev) - min(mean_rev) FROM tpch_changepoints(2, 3, 20)) > 15,
  'changepoints: means diverge');

WITH c AS (SELECT * FROM tpch_supplier_kmeans(2, 25))
SELECT plecl_expect(
  (SELECT count(DISTINCT cluster) FROM c WHERE supplier BETWEEN 10 AND 14) = 1
  AND (SELECT count(DISTINCT cluster) FROM c WHERE supplier BETWEEN 20 AND 24) = 1
  AND (SELECT min(cluster) FROM c WHERE supplier BETWEEN 10 AND 14)
      <> (SELECT min(cluster) FROM c WHERE supplier BETWEEN 20 AND 24),
  'kmeans: two well-separated blobs');

SELECT plecl_expect(
  (SELECT count(*) FROM tpch_holt_winters(3, 4, 4) WHERE actual IS NULL) = 4,
  'holt-winters: 4 forecast rows');
SELECT plecl_expect(
  (SELECT bool_and(yhat IS NOT NULL) FROM tpch_holt_winters(3, 4, 4)),
  'holt-winters: yhat present');

SELECT plecl_expect(
  (SELECT count(*) FROM tpch_late_viterbi(2)) = 16,
  'viterbi: one row per day');
SELECT plecl_expect(
  (SELECT bool_or(state = 'late') FROM tpch_late_viterbi(2)),
  'viterbi: sees a late regime');
