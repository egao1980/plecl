-- Call shapes (plpython_call / plpython_params)

CREATE FUNCTION t_lambda(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(lambda (n) (* n 3))
$plecl$;
SELECT plecl_expect(t_lambda(5) = 15, 'explicit lambda body');

CREATE FUNCTION t_progn(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(setf n (+ n 1))
(* n 2)
$plecl$;
SELECT plecl_expect(t_progn(3) = 8, 'multi-form progn');

CREATE FUNCTION t_replace_me(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (+ n 1) $plecl$;
SELECT plecl_expect(t_replace_me(1) = 2, 'before replace');

CREATE OR REPLACE FUNCTION t_replace_me(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (+ n 10) $plecl$;
SELECT plecl_expect(t_replace_me(1) = 11, 'CREATE OR REPLACE invalidates cache');

CREATE FUNCTION t_pleclu(n integer) RETURNS integer
LANGUAGE pleclu STRICT AS $plecl$ (+ n 1) $plecl$;
SELECT plecl_expect(t_pleclu(9) = 10, 'LANGUAGE pleclu alias');

CREATE FUNCTION t_dollar_body(n integer) RETURNS text
LANGUAGE plecl STRICT AS $p0$
(concatenate 'string "has $plecl$ tag " (princ-to-string n))
$p0$;
SELECT plecl_expect(t_dollar_body(1) = 'has $plecl$ tag 1', 'dollar-quote collision body');

CREATE FUNCTION t_two_args(a integer, b integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$ (+ a b) $plecl$;
SELECT plecl_expect(t_two_args(2, 40) = 42, 'two named args');
