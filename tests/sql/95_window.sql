-- Demo window aggregate created from SQL (not an extension primitive).
\ir ../../examples/window-agg.sql

SELECT plecl_expect(
  (SELECT count(*) FROM demo_sales_window(1)) = 6,
  'window row count');

SELECT plecl_expect(
  (SELECT running_sum FROM demo_sales_window(1) WHERE store = 'east' AND day = 4) = 100,
  'east running sum');

SELECT plecl_expect(
  (SELECT share FROM demo_sales_window(1) WHERE store = 'west' AND day = 2) = 0.75,
  'west share');

SELECT plecl_expect(
  (SELECT lag_amount IS NULL FROM demo_sales_window(1) WHERE store = 'east' AND day = 1),
  'first lag is null');

SELECT plecl_expect(
  (SELECT rank FROM demo_sales_window(1) WHERE store = 'east' AND day = 1) = 1,
  'rank on amount');
