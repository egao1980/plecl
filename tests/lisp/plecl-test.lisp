(in-package #:plecl/tests)

(deftest dollar-quote-plain
  (ok (string= (dollar-quote "(1+ n)") "$plecl$(1+ n)$plecl$")))

(deftest dollar-quote-avoids-collision
  (let ((sql (dollar-quote "x $plecl$ y")))
    (ok (not (and (>= (length sql) 7) (string= (subseq sql 0 7) "$plecl$")))
        "outer tag is not $plecl$ when that appears in the body")
    (ok (char= (char sql 0) #\$))
    (ok (search "x $plecl$ y" sql))))

(deftest dollar-quote-corpus
  (dolist (src (list "" "(+ 1 2)" "$$$" "a $x$ b" "$$$tag$$$"))
    (let ((q (dollar-quote src)))
      (ok (and (char= (char q 0) #\$) (search src q))
          (format nil "dollar-quote ~s" src)))))

(deftest function-sql-replace
  (let ((sql (function-sql "add1" '("n integer") "integer" "(1+ n)" :replace t)))
    (ok (search "CREATE OR REPLACE FUNCTION add1(n integer)" sql))
    (ok (search "RETURNS integer" sql))
    (ok (search "LANGUAGE plecl" sql))
    (ok (search "$plecl$(1+ n)$plecl$" sql))))

(deftest function-sql-pleclu
  (let ((sql (function-sql "f" '() "void" "nil" :language :pleclu)))
    (ok (search "LANGUAGE pleclu" sql))
    (ok (search "FUNCTION f()" sql))))

(deftest sql-null
  (ok (sql-null-p +null+))
  (ng (sql-null-p nil))
  (ng (sql-null-p 0)))
