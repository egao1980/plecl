(in-package #:plecl/tests)

(deftest pack-roundtrip-and-load-source
  (let* ((src "(defparameter *blob-probe* 41)")
         (octets (plecl::string-to-utf8 src)))
    (load-blob octets "probe" "lisp")
    (ok (= 41 (symbol-value (find-symbol "*BLOB-PROBE*" :plecl.user))))))

(deftest pack-system-unpacks-files
  (let* ((packed (pack-system
                  '(("blob-demo.asd"
                     . "(defsystem \"blob-demo\" :serial t :components ((:file \"pkg\") (:file \"cube\")))")
                    ("pkg.lisp" . "(defpackage #:blob-demo (:use #:cl) (:export #:cube))")
                    ("cube.lisp" . "(in-package #:blob-demo) (defun cube (x) (* x x x))"))))
         (dir (merge-pathnames (format nil "plecl-blob-test-~d/" (random 100000))
                               (user-homedir-pathname)))
         (written (unpack-system packed dir)))
    (ok (= 3 (length written)))
    (ok (probe-file (merge-pathnames "pkg.lisp" dir)))
    (ok (probe-file (merge-pathnames "cube.lisp" dir)))
    (load-blob packed "blob-demo" "system")
    (ok (= 27 (funcall (find-symbol "CUBE" :blob-demo) 3)))))

(deftest reject-dotdot-path
  (ok (signals (pack-system '(("../x.lisp" . "(+ 1 2)"))) 'error)))

(deftest vendor-asdf-present
  (let ((path (merge-pathnames "vendor/asdf.lisp"
                               (make-pathname :name nil :type nil
                                              :defaults (asdf:system-source-file "plecl")))))
    (ok (probe-file path))
    (ok (search "This is ASDF 3.3.7"
                (with-open-file (in path) (read-line in) (read-line in))))))
