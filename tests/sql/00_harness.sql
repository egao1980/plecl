-- Harness (plpython/plguile3 style): fail the script on a wrong value, not just SQL errors.
SET statement_timeout = '180s';
\echo creating extension
CREATE EXTENSION IF NOT EXISTS plecl;
\echo extension ok

CREATE FUNCTION plecl_expect(ok boolean, msg text DEFAULT 'assertion failed')
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN
    RAISE EXCEPTION 'plecl test failed: %', msg;
  END IF;
END$$;
