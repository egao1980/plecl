-- Errors (plpython_error / ereport)

CREATE FUNCTION err_boom() RETURNS integer
LANGUAGE plecl AS $plecl$
(error "boom")
$plecl$;

DO $$
DECLARE
  msg text;
BEGIN
  BEGIN
    PERFORM err_boom();
    RAISE EXCEPTION 'should have failed';
  EXCEPTION
    WHEN external_routine_exception THEN
      GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
      IF position('boom' in msg) = 0 THEN
        RAISE EXCEPTION 'err_boom SQLERRM missing boom: %', msg;
      END IF;
  END;
END$$;

CREATE FUNCTION err_debugger() RETURNS integer
LANGUAGE plecl AS $plecl$
(invoke-debugger (make-condition 'simple-error :format-control "dbg-hook"))
$plecl$;

DO $$
DECLARE
  msg text;
BEGIN
  BEGIN
    PERFORM err_debugger();
    RAISE EXCEPTION 'debugger hook should have failed';
  EXCEPTION
    WHEN external_routine_exception THEN
      GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
      IF position('dbg-hook' in msg) = 0 THEN
        RAISE EXCEPTION 'debugger hook SQLERRM missing dbg-hook: %', msg;
      END IF;
  END;
END$$;

CREATE FUNCTION err_type () RETURNS integer
LANGUAGE plecl AS $plecl$
(float nil 1.0d0)
$plecl$;

DO $$
DECLARE
  msg text;
BEGIN
  BEGIN
    PERFORM err_type();
    RAISE EXCEPTION 'type-error should have failed';
  EXCEPTION
    WHEN external_routine_exception THEN
      GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
      IF position('REAL' in msg) = 0 AND position('real' in msg) = 0 THEN
        RAISE EXCEPTION 'type-error SQLERRM unexpected: %', msg;
      END IF;
  END;
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
  WHEN undefined_column THEN
    NULL; -- SPI surfaces the real SQLSTATE
  WHEN external_routine_exception THEN
    NULL;
END$$;
