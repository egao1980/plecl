-- Errors (plpython_error / ereport)

CREATE FUNCTION err_boom() RETURNS integer
LANGUAGE plecl AS $plecl$
(error "boom")
$plecl$;

DO $$
BEGIN
  PERFORM err_boom();
  RAISE EXCEPTION 'should have failed';
EXCEPTION
  WHEN external_routine_exception THEN
    NULL;
END$$;

DO $$
BEGIN
  CREATE FUNCTION err_bad_read() RETURNS integer
  LANGUAGE plecl AS $plecl$ (  $plecl$;
  RAISE EXCEPTION 'validator should have failed';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END$$;

CREATE FUNCTION err_spi() RETURNS integer
LANGUAGE plecl AS $plecl$
(plecl:query-value "SELECT no_such_column FROM spi_t")
$plecl$;

DO $$
BEGIN
  PERFORM err_spi();
  RAISE EXCEPTION 'SPI error should have failed';
EXCEPTION
  WHEN external_routine_exception THEN
    NULL;
END$$;
