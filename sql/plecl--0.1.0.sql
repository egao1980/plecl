CREATE FUNCTION plecl_call_handler()
RETURNS language_handler
AS 'MODULE_PATHNAME', 'plecl_call_handler'
LANGUAGE C STRICT;

CREATE FUNCTION plecl_inline_handler(internal)
RETURNS void
AS 'MODULE_PATHNAME', 'plecl_inline_handler'
LANGUAGE C STRICT;

CREATE FUNCTION plecl_validator(oid)
RETURNS void
AS 'MODULE_PATHNAME', 'plecl_validator'
LANGUAGE C STRICT;

CREATE LANGUAGE plecl
  HANDLER plecl_call_handler
  INLINE plecl_inline_handler
  VALIDATOR plecl_validator;

COMMENT ON LANGUAGE plecl IS
  'Common Lisp (ECL) procedural language — untrusted, full ECL';

CREATE FUNCTION pleclu_call_handler()
RETURNS language_handler
AS 'MODULE_PATHNAME', 'plecl_call_handler'
LANGUAGE C STRICT;

CREATE FUNCTION pleclu_inline_handler(internal)
RETURNS void
AS 'MODULE_PATHNAME', 'plecl_inline_handler'
LANGUAGE C STRICT;

CREATE FUNCTION pleclu_validator(oid)
RETURNS void
AS 'MODULE_PATHNAME', 'plecl_validator'
LANGUAGE C STRICT;

CREATE LANGUAGE pleclu
  HANDLER pleclu_call_handler
  INLINE pleclu_inline_handler
  VALIDATOR pleclu_validator;

COMMENT ON LANGUAGE pleclu IS
  'Alias of plecl (untrusted Common Lisp)';

-- Inspector catalog: schema lisp is the "table space" over the ECL image.
CREATE SCHEMA lisp;
COMMENT ON SCHEMA lisp IS
  'ECL image inspector — views over packages, symbols, functions, features, cache';

CREATE TYPE lisp.inspect_row AS (
  path text,
  kind text,
  type text,
  value text,
  length integer
);

CREATE TYPE lisp.package_row AS (
  name text,
  nicknames text[],
  n_external integer,
  n_internal integer,
  used text[],
  used_by text[]
);

CREATE TYPE lisp.symbol_row AS (
  package text,
  name text,
  accessibility text,
  boundp boolean,
  fboundp boolean,
  value text,
  function_type text,
  documentation text
);

CREATE TYPE lisp.feature_row AS (
  feature text
);

CREATE TYPE lisp.cache_row AS (
  oid bigint,
  xmin bigint,
  boundp boolean
);

CREATE TYPE lisp.image_row AS (
  implementation text,
  version text,
  n_packages integer,
  n_cached integer,
  n_features integer
);

CREATE FUNCTION lisp.inspect(ref text, depth integer DEFAULT 3)
RETURNS SETOF lisp.inspect_row
LANGUAGE plecl AS $plecl$
(plecl:inspect-ref ref depth)
$plecl$;

CREATE FUNCTION lisp.package_rows()
RETURNS SETOF lisp.package_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-packages)
$plecl$;

CREATE FUNCTION lisp.symbol_rows(package_name text DEFAULT NULL)
RETURNS SETOF lisp.symbol_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-symbols package_name)
$plecl$;

CREATE FUNCTION lisp.function_rows(package_name text DEFAULT NULL)
RETURNS SETOF lisp.symbol_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-functions package_name)
$plecl$;

CREATE FUNCTION lisp.special_rows(package_name text DEFAULT NULL)
RETURNS SETOF lisp.symbol_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-specials package_name)
$plecl$;

CREATE FUNCTION lisp.feature_rows()
RETURNS SETOF lisp.feature_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-features)
$plecl$;

CREATE FUNCTION lisp.cache_rows()
RETURNS SETOF lisp.cache_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-cache)
$plecl$;

CREATE FUNCTION lisp.image_rows()
RETURNS SETOF lisp.image_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-image)
$plecl$;

CREATE VIEW lisp.packages AS SELECT * FROM lisp.package_rows();
CREATE VIEW lisp.symbols AS SELECT * FROM lisp.symbol_rows();
CREATE VIEW lisp.functions AS SELECT * FROM lisp.function_rows();
CREATE VIEW lisp.specials AS SELECT * FROM lisp.special_rows();
CREATE VIEW lisp.features AS SELECT * FROM lisp.feature_rows();
CREATE VIEW lisp.cache AS SELECT * FROM lisp.cache_rows();
CREATE VIEW lisp.image AS SELECT * FROM lisp.image_rows();

COMMENT ON VIEW lisp.packages IS 'list-all-packages + use/used-by + symbol counts';
COMMENT ON VIEW lisp.symbols IS 'home symbols of PLECL, PLECL.USER, CL-USER (or lisp.symbol_rows(pkg))';
COMMENT ON VIEW lisp.functions IS 'fbound subset of lisp.symbols';
COMMENT ON VIEW lisp.specials IS 'boundp subset of lisp.symbols';
COMMENT ON VIEW lisp.features IS '*features*';
COMMENT ON VIEW lisp.cache IS 'plecl function cache (oid, xmin)';
COMMENT ON VIEW lisp.image IS 'implementation / counts for the embedded ECL image';
COMMENT ON FUNCTION lisp.inspect(text, integer) IS
  'Walk a symbol, package, or *read-eval*-nil form (e.g. "(list 1 2)")';

CREATE TABLE lisp.systems (
  name text PRIMARY KEY,
  payload bytea NOT NULL,
  format text NOT NULL DEFAULT 'auto',
  loaded_at timestamptz
);

COMMENT ON TABLE lisp.systems IS
  'Lisp source or packed ASDF tree (PLECLSYS1) as bytea; load with lisp.load_system(name)';

CREATE TYPE lisp.loaded_row AS (
  name text,
  format text,
  directory text
);

CREATE FUNCTION lisp.load_blob(payload bytea, name text DEFAULT 'blob', format text DEFAULT 'auto')
RETURNS text
LANGUAGE plecl AS $plecl$
(plecl:load-blob payload name format)
$plecl$;

CREATE FUNCTION lisp.load_system(name text)
RETURNS text
LANGUAGE plecl AS $plecl$
(plecl:load-system name)
$plecl$;

CREATE FUNCTION lisp.store_system(name text, payload bytea, format text DEFAULT 'auto')
RETURNS text
LANGUAGE plecl AS $plecl$
(plecl:store-system name payload format)
$plecl$;

CREATE FUNCTION lisp.loaded_rows()
RETURNS SETOF lisp.loaded_row
LANGUAGE plecl AS $plecl$
(plecl:catalog-loaded)
$plecl$;

CREATE VIEW lisp.loaded AS SELECT * FROM lisp.loaded_rows();

COMMENT ON FUNCTION lisp.load_blob(bytea, text, text) IS
  'Load UTF-8 Lisp source or a PLECLSYS1 packed system from bytea';
COMMENT ON FUNCTION lisp.load_system(text) IS
  'Load a row from lisp.systems into the ECL image';
COMMENT ON FUNCTION lisp.store_system(text, bytea, text) IS
  'UPSERT lisp.systems and load it';
COMMENT ON VIEW lisp.loaded IS 'Systems loaded from blobs in this backend';

CREATE FUNCTION lisp.asdf_version()
RETURNS text
LANGUAGE plecl AS $plecl$
(plecl:asdf-version-string)
$plecl$;

COMMENT ON FUNCTION lisp.asdf_version() IS
  'ASDF version loaded into the backend (bundled 3.3.7)';
