-- Inspector catalog (schema lisp)

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.packages
    WHERE name IN ('PLECL', 'PLECL.USER', 'COMMON-LISP')) = 3,
  'lisp.packages');

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.symbols
    WHERE package = 'PLECL' AND name IN ('+NULL+', 'QUERY', 'INSPECT-REF', 'LOAD-BLOB')) = 4,
  'lisp.symbols');

SELECT plecl_expect(
  (SELECT n_packages > 0 FROM lisp.image),
  'lisp.image');

SELECT plecl_expect(
  (SELECT count(*) > 0 FROM lisp.features WHERE feature IN ('ECL', 'COMMON-LISP')),
  'lisp.features');

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.inspect('(cons 1 2)', 2) WHERE kind IN ('cons', 'atom')) >= 3,
  'lisp.inspect cons');

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.inspect('PLECL:+NULL+', 1) WHERE kind = 'symbol') >= 1,
  'lisp.inspect symbol');

SELECT plecl_expect(lisp.asdf_version() = '3.3.7', 'bundled ASDF 3.3.7');

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.functions WHERE package = 'PLECL' AND name = 'QUERY') = 1,
  'lisp.functions');
