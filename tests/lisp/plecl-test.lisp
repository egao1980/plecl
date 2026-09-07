(in-package #:plecl/tests)

(deftest dollar-quote-plain
  (ok (string= (dollar-quote "(1+ n)") "$plecl$(1+ n)$plecl$")))

(deftest dollar-quote-avoids-collision
  (let ((sql (dollar-quote "x $plecl$ y")))
    (ok (not (and (>= (length sql) 7) (string= (subseq sql 0 7) "$plecl$")))
        "outer tag is not $plecl$ when that appears in the body")
    (ok (char= (char sql 0) #\$))
    (ok (search "x $plecl$ y" sql))))

(deftest function-sql-replace
  (let ((sql (function-sql "add1" '("n integer") "integer" "(1+ n)" :replace t)))
    (ok (search "CREATE OR REPLACE FUNCTION add1(n integer)" sql))
    (ok (search "RETURNS integer" sql))
    (ok (search "LANGUAGE plecl" sql))
    (ok (search "$plecl$(1+ n)$plecl$" sql))))
