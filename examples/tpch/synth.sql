-- Skewed TPC-H-shaped lineitem. :n = 6000000 is ~1GB / SF1 cardinality.
-- Supplier 1 gets 5% of rows so interval/HMM/HW have a fat partition.
TRUNCATE lineitem;

INSERT INTO lineitem (
  l_orderkey, l_partkey, l_suppkey, l_linenumber,
  l_quantity, l_extendedprice, l_discount, l_tax,
  l_returnflag, l_linestatus,
  l_shipdate, l_commitdate, l_receiptdate,
  l_shipinstruct, l_shipmode, l_comment
)
SELECT
  (g / 4) + 1,
  1 + (g % 200000),
  CASE WHEN (g % 20) = 0 THEN 1 ELSE 1 + (g % 9999) END,
  1 + (g % 4),
  (1 + (g % 50))::float8,
  (100 + (g % 900))::float8,
  ((g % 11) * 0.01)::float8,
  0.08,
  CASE WHEN (g % 17) = 0 THEN 'R' ELSE 'A' END,
  'O',
  DATE '1992-01-01' + ((g * 3) % 2400),
  DATE '1992-01-01' + ((g * 3) % 2400) - 4,
  DATE '1992-01-01' + ((g * 3) % 2400) + 2 + (g % 9),
  'DELIVER IN PERSON',
  CASE WHEN (g % 2) = 0 THEN 'AIR' ELSE 'SHIP' END,
  'synth'
FROM generate_series(1, :n) g;

ANALYZE lineitem;
