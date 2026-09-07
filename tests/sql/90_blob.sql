-- System loader from bytea

SELECT plecl_expect(
  lisp.store_system(
    'demo-add',
    convert_to(
      '(defpackage #:demo-add (:use #:cl) (:export #:add2))
       (in-package #:demo-add)
       (defun add2 (x) (+ x 2))',
      'UTF8'),
    'lisp') = 'loaded:demo-add',
  'store+load source blob');

CREATE FUNCTION demo_add2(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(demo-add:add2 n)
$plecl$;

SELECT plecl_expect(demo_add2(40) = 42, 'call function from blob');
SELECT plecl_expect(
  (SELECT format FROM lisp.loaded WHERE name = 'demo-add') = 'lisp',
  'lisp.loaded');

DO LANGUAGE plecl $plecl$
(plecl:store-system
 "demo-mul"
 (plecl:pack-system
  '(("demo-mul.asd"
     . "(defsystem \"demo-mul\" :serial t :components ((:file \"pkg\") (:file \"mul\")))")
    ("pkg.lisp" . "(defpackage #:demo-mul (:use #:cl) (:export #:mul2))")
    ("mul.lisp" . "(in-package #:demo-mul) (defun mul2 (x) (* x 2))")))
 "system")
$plecl$;

CREATE FUNCTION demo_mul2(n integer) RETURNS integer
LANGUAGE plecl STRICT AS $plecl$
(demo-mul:mul2 n)
$plecl$;

SELECT plecl_expect(demo_mul2(21) = 42, 'packed ASDF system from blob');

DO $$
BEGIN
  PERFORM lisp.load_blob(convert_to('ignored', 'UTF8'), '../evil', 'lisp');
  RAISE EXCEPTION 'path traversal should have failed';
EXCEPTION
  WHEN external_routine_exception THEN
    NULL;
END$$;

SELECT plecl_expect(
  (SELECT count(*) FROM lisp.systems WHERE name IN ('demo-add', 'demo-mul')) = 2,
  'lisp.systems rows');
