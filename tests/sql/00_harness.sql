-- Harness (plpython/plguile3 style): fail the script on a wrong value, not just SQL errors.
SET statement_timeout = '60s';
CREATE EXTENSION IF NOT EXISTS plecl;

CREATE FUNCTION plecl_expect(ok boolean, msg text DEFAULT 'assertion failed')
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN
    RAISE EXCEPTION 'plecl test failed: %', msg;
  END IF;
END$$;
