(defsystem "plecl"
  :version "0.1.0"
  :description "PostgreSQL procedural language — Embeddable Common Lisp (client helpers)"
  :author "egao1980"
  :license "MIT"
  :pathname "lisp"
  :serial t
  :components ((:file "package")
               (:file "inspect")
               (:file "blob")
               (:file "client"))
  :in-order-to ((test-op (test-op "plecl/tests"))))

(defsystem "plecl/tests"
  :depends-on ("plecl" "rove")
  :pathname "tests/lisp"
  :serial t
  :components ((:file "package")
               (:file "plecl-test")
               (:file "inspect-test")
               (:file "blob-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
