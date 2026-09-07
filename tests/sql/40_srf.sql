-- Set-returning (plpython setof / composite)

CREATE FUNCTION srf_series(n integer) RETURNS SETOF integer
LANGUAGE plecl STRICT AS $plecl$
(loop for i from 1 to n collect i)
$plecl$;
SELECT plecl_expect((SELECT count(*) FROM srf_series(3)) = 3, 'srf count');
SELECT plecl_expect((SELECT sum(s) FROM srf_series(4) s) = 10, 'srf sum');
SELECT plecl_expect((SELECT count(*) FROM srf_series(0)) = 0, 'srf empty');

CREATE FUNCTION srf_atom(n integer) RETURNS SETOF integer
LANGUAGE plecl STRICT AS $plecl$ n $plecl$;
SELECT plecl_expect((SELECT count(*) FROM srf_atom(7)) = 1, 'non-list SRF boxed as one row');

CREATE TYPE srf_pair AS (a integer, b text);

CREATE FUNCTION srf_pairs() RETURNS SETOF srf_pair
LANGUAGE plecl AS $plecl$
(list (list (cons :a 1) (cons :b "x"))
      (list (cons :a 2) (cons :b "y")))
$plecl$;
SELECT plecl_expect((SELECT b FROM srf_pairs() WHERE a = 2) = 'y', 'srf composite alist');

CREATE FUNCTION srf_texts() RETURNS SETOF text
LANGUAGE plecl AS $plecl$
(list "α" "β")
$plecl$;
SELECT plecl_expect((SELECT string_agg(t, ',') FROM srf_texts() t) = 'α,β', 'srf unicode text');
