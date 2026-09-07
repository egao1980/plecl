(defpackage #:plecl
  (:use #:cl)
  (:export #:dollar-quote
           #:function-sql
           #:plecl-error
           #:+null+
           #:sql-null-p
           #:inspect-ref
           #:catalog-packages
           #:catalog-symbols
           #:catalog-functions
           #:catalog-specials
           #:catalog-features
           #:catalog-cache
           #:catalog-image
           #:pack-system
           #:unpack-system
           #:load-blob
           #:load-system
           #:store-system
           #:catalog-loaded
           #:load-bundled-asdf
           #:asdf-version-string))

(in-package #:plecl)

(defconstant +null+ '+sql-null+)

(defun sql-null-p (x)
  (eq x +null+))

(defpackage #:plecl.user
  (:use #:cl #:plecl))
