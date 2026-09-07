(in-package #:plecl/tests)

(defun %iref (row key)
  (cdr (assoc key row)))

(deftest inspect-cons
  (let ((rows (inspect-ref "(cons 1 2)" 2)))
    (ok (plusp (length rows)))
    (ok (find "cons" rows :key (lambda (r) (%iref r :kind)) :test #'string=))
    (ok (find "atom" rows :key (lambda (r) (%iref r :kind)) :test #'string=))))

(deftest inspect-symbol-and-package
  (let ((sym (inspect-ref "PLECL:+NULL+" 2))
        (pkg (inspect-ref "PLECL" 1)))
    (ok (find "symbol" sym :key (lambda (r) (%iref r :kind)) :test #'string=))
    (ok (find "package" pkg :key (lambda (r) (%iref r :kind)) :test #'string=))))

(deftest catalog-packages-includes-cl
  (let ((names (mapcar (lambda (r) (%iref r :name)) (catalog-packages))))
    (ok (find "COMMON-LISP" names :test #'string=))
    (ok (find "PLECL" names :test #'string=))))

(deftest catalog-symbols-plecl
  (let ((names (mapcar (lambda (r) (%iref r :name))
                       (catalog-symbols "PLECL"))))
    (ok (find "+NULL+" names :test #'string=))
    (ok (find "INSPECT-REF" names :test #'string=))))

(deftest catalog-image-smoke
  (let ((row (first (catalog-image))))
    (ok (stringp (%iref row :implementation)))
    (ok (plusp (%iref row :n_packages)))
    (ok (plusp (%iref row :n_features)))))

(deftest catalog-features-nonempty
  (ok (plusp (length (catalog-features)))))
