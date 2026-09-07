-- SPI (plpython_spi)

CREATE TABLE spi_t(id integer PRIMARY KEY, n integer, label text);
INSERT INTO spi_t VALUES (1, 10, 'a'), (2, 20, 'b');

CREATE FUNCTION spi_sum() RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT COALESCE(SUM(n),0)::int FROM spi_t")
$plecl$;
SELECT plecl_expect(spi_sum() = 30, 'query-value sum');

CREATE FUNCTION spi_nrows() RETURNS integer
LANGUAGE plecl AS $plecl$
(length (plecl:query "SELECT id FROM spi_t ORDER BY id"))
$plecl$;
SELECT plecl_expect(spi_nrows() = 2, 'query row count');

CREATE FUNCTION spi_empty() RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT n FROM spi_t WHERE id = 999")
$plecl$;
SELECT plecl_expect(spi_empty() IS NULL, 'query-value empty → +null+');

CREATE FUNCTION spi_by_id(id integer) RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT n FROM spi_t WHERE id = $1" id)
$plecl$;
SELECT plecl_expect(spi_by_id(2) = 20, 'bind $1');

CREATE FUNCTION spi_bump(id integer, by integer) RETURNS integer
LANGUAGE plecl AS $plecl$
(progn
  (plecl:execute "UPDATE spi_t SET n = n + $1 WHERE id = $2" by id)
  (plecl:query-value "SELECT n FROM spi_t WHERE id = $1" id))
$plecl$;
SELECT plecl_expect(spi_bump(1, 5) = 15, 'DML execute + reread');

CREATE FUNCTION spi_insert_null_label(id integer) RETURNS text
LANGUAGE plecl AS $plecl$
(progn
  (plecl:execute "INSERT INTO spi_t(id, n, label) VALUES ($1, 0, $2)" id plecl:+null+)
  (plecl:query-value "SELECT label FROM spi_t WHERE id = $1" id))
$plecl$;
SELECT plecl_expect(spi_insert_null_label(3) IS NULL, 'bind +null+ as SQL NULL');
