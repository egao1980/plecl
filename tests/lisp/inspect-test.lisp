(in-package #:plecl/tests)

(defun %iref (row key)
  (cdr (assoc key row)))

(defun %kinds (rows)
  (mapcar (lambda (r) (%iref r :kind)) rows))

(deftest inspect-cons
  (let ((rows (inspect-ref "(cons 1 2)" 2)))
    (ok (plusp (length rows)))
    (ok (find "cons" (%kinds rows) :test #'string=))
    (ok (find "atom" (%kinds rows) :test #'string=))))

(deftest inspect-list
  (let ((rows (inspect-ref "(list 1 2 3)" 2)))
    (ok (find "list" (%kinds rows) :test #'string=))
    (ok (>= (count "atom" (%kinds rows) :test #'string=) 3))))

(deftest inspect-hash-table
  (let ((rows (inspect-ref "(let ((h (make-hash-table))) (setf (gethash :k h) 1) h)" 2)))
    (ok (find "hash-table" (%kinds rows) :test #'string=))))

(deftest inspect-vector
  (let ((rows (inspect-ref "(vector 1 2)" 2)))
    (ok (find "array" (%kinds rows) :test #'string=))))

(deftest inspect-cycle
  (let ((rows (inspect-ref "(let ((c (cons 1 nil))) (setf (cdr c) c) c)" 4)))
    (ok (find "cycle" (%kinds rows) :test #'string=))))

(deftest inspect-symbol-and-package
  (let ((sym (inspect-ref "PLECL:+NULL+" 2))
        (pkg (inspect-ref "PLECL" 1)))
    (ok (find "symbol" (%kinds sym) :test #'string=))
    (ok (find "package" (%kinds pkg) :test #'string=))))

(deftest inspect-unknown-ref
  (ok (signals (inspect-ref "NO-SUCH-PKG:FOO") 'error))
  (ok (signals (inspect-ref "") 'error)))

(deftest catalog-packages-includes-cl
  (let ((names (mapcar (lambda (r) (%iref r :name)) (catalog-packages))))
    (ok (find "COMMON-LISP" names :test #'string=))
    (ok (find "PLECL" names :test #'string=))))

(deftest catalog-symbols-plecl
  (let ((names (mapcar (lambda (r) (%iref r :name))
                       (catalog-symbols "PLECL"))))
    (ok (find "+NULL+" names :test #'string=))
    (ok (find "INSPECT-REF" names :test #'string=))))

(deftest catalog-functions-plecl
  (let ((names (mapcar (lambda (r) (%iref r :name))
                       (catalog-functions "PLECL"))))
    (ok (find "INSPECT-REF" names :test #'string=))
    (ok (not (find "+NULL+" names :test #'string=)))))

(deftest catalog-image-smoke
  (let ((row (first (catalog-image))))
    (ok (stringp (%iref row :implementation)))
    (ok (plusp (%iref row :n_packages)))
    (ok (plusp (%iref row :n_features)))))

(deftest catalog-features-nonempty
  (ok (plusp (length (catalog-features)))))
