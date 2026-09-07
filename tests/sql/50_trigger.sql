-- Triggers (plpython_trigger)

CREATE TABLE tg_t(id integer PRIMARY KEY, n integer);

CREATE FUNCTION tg_double() RETURNS trigger
LANGUAGE plecl AS $plecl$
(let ((new (copy-list (plecl:trigger-new))))
  (setf (cdr (assoc :n new)) (* 2 (cdr (assoc :n new))))
  new)
$plecl$;

CREATE TRIGGER tg_double_bi
  BEFORE INSERT ON tg_t
  FOR EACH ROW
  EXECUTE FUNCTION tg_double();

INSERT INTO tg_t VALUES (1, 11);
SELECT plecl_expect((SELECT n FROM tg_t WHERE id = 1) = 22, 'BEFORE INSERT rewrite NEW');

CREATE FUNCTION tg_skip_neg() RETURNS trigger
LANGUAGE plecl AS $plecl$
(if (minusp (cdr (assoc :n (plecl:trigger-new))))
    :skip
    :ok)
$plecl$;

CREATE TRIGGER tg_skip_bi
  BEFORE INSERT ON tg_t
  FOR EACH ROW
  EXECUTE FUNCTION tg_skip_neg();

INSERT INTO tg_t VALUES (2, -3);
SELECT plecl_expect((SELECT count(*) FROM tg_t WHERE id = 2) = 0, 'trigger :skip');
INSERT INTO tg_t VALUES (2, 4);
SELECT plecl_expect((SELECT n FROM tg_t WHERE id = 2) = 8, 'trigger :ok then double');

CREATE FUNCTION tg_op_name() RETURNS trigger
LANGUAGE plecl AS $plecl$
(progn
  (plecl:execute "INSERT INTO tg_audit(op, name) VALUES ($1, $2)"
                 (symbol-name (plecl:trigger-op))
                 (plecl:trigger-name))
  :ok)
$plecl$;

CREATE TABLE tg_audit(op text, name text);

CREATE TRIGGER tg_audit_ai
  AFTER INSERT ON tg_t
  FOR EACH ROW
  EXECUTE FUNCTION tg_op_name();

INSERT INTO tg_t VALUES (3, 1);
SELECT plecl_expect((SELECT op FROM tg_audit LIMIT 1) = 'INSERT', 'tg-op');
SELECT plecl_expect((SELECT name FROM tg_audit LIMIT 1) = 'tg_audit_ai', 'tg-name');

-- Isolated UPDATE/DELETE table (plpython_trigger).
CREATE TABLE tg_ud(id integer PRIMARY KEY, n integer);
INSERT INTO tg_ud VALUES (1, 10);

CREATE FUNCTION tg_inc_on_update() RETURNS trigger
LANGUAGE plecl AS $plecl$
(let ((new (copy-list (plecl:trigger-new))))
  (setf (cdr (assoc :n new)) (+ (cdr (assoc :n new)) 1))
  new)
$plecl$;

CREATE TRIGGER tg_inc_bu
  BEFORE UPDATE ON tg_ud
  FOR EACH ROW
  EXECUTE FUNCTION tg_inc_on_update();

UPDATE tg_ud SET n = 20 WHERE id = 1;
SELECT plecl_expect((SELECT n FROM tg_ud WHERE id = 1) = 21, 'BEFORE UPDATE rewrite NEW');

CREATE FUNCTION tg_skip_del_even() RETURNS trigger
LANGUAGE plecl AS $plecl$
(if (evenp (cdr (assoc :n (plecl:trigger-old))))
    :skip
    :ok)
$plecl$;

CREATE TRIGGER tg_skip_bd
  BEFORE DELETE ON tg_ud
  FOR EACH ROW
  EXECUTE FUNCTION tg_skip_del_even();

INSERT INTO tg_ud VALUES (2, 10);
DELETE FROM tg_ud WHERE id = 2;
SELECT plecl_expect((SELECT count(*) FROM tg_ud WHERE id = 2) = 1, 'BEFORE DELETE :skip even');
INSERT INTO tg_ud VALUES (3, 11);
DELETE FROM tg_ud WHERE id = 3;
SELECT plecl_expect((SELECT count(*) FROM tg_ud WHERE id = 3) = 0, 'BEFORE DELETE :ok odd');
