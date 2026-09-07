(in-package #:plecl/tests)

(deftest pack-roundtrip-and-load-source
  (let* ((src "(defparameter *blob-probe* 41)")
         (octets (plecl::string-to-utf8 src)))
    (load-blob octets "probe" "lisp")
    (ok (= 41 (symbol-value (find-symbol "*BLOB-PROBE*" :plecl.user))))))

(deftest load-blob-from-string
  (load-blob "(defparameter *blob-str* :ok)" "s" "lisp")
  (ok (eq :ok (symbol-value (find-symbol "*BLOB-STR*" :plecl.user)))))

(deftest utf8-roundtrip
  (dolist (s '("" "ascii" "café" "αβγ" "🙂"))
    (ok (string= s (plecl::utf8-to-string (plecl::string-to-utf8 s)))
        (format nil "utf8 ~s" s))))

(deftest detect-packed-vs-source
  (let ((src (plecl::string-to-utf8 "(+ 1 2)"))
        (packed (pack-system '(("a.lisp" . "(+ 1 2)")))))
    (ok (eq :lisp (plecl::detect-blob-format src "auto")))
    (ok (eq :system (plecl::detect-blob-format packed "auto")))
    (ok (eq :lisp (plecl::detect-blob-format packed "lisp")))))

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
    (ok (= 27 (funcall (find-symbol "CUBE" :blob-demo) 3)))
    (ok (find "blob-demo" (mapcar (lambda (r) (cdr (assoc :name r))) (catalog-loaded))
              :test #'string=))))

(deftest reject-illegal-paths
  (ok (signals (pack-system '(("../x.lisp" . "(+ 1 2)"))) 'error))
  (ok (signals (pack-system '(("/etc/passwd" . "x"))) 'error)))

(deftest empty-payload
  (ok (signals (load-blob +null+ "x" "lisp") 'error)))

(deftest vendor-asdf-present
  (let ((path (merge-pathnames "vendor/asdf.lisp"
                               (make-pathname :name nil :type nil
                                              :defaults (asdf:system-source-file "plecl")))))
    (ok (probe-file path))
    (ok (search "This is ASDF 3.3.7"
                (with-open-file (in path) (read-line in) (read-line in))))))

(deftest backend-lisp-no-uiop-reader
  ;; blob.lisp is LOADed into ECL before ASDF/UIOP exists. A `uiop:` token
  ;; at read time drops the backend into the debugger and hangs CREATE EXTENSION.
  (let* ((root (make-pathname :name nil :type nil
                              :defaults (asdf:system-source-file "plecl")))
         (paths (list (merge-pathnames "lisp/blob.lisp" root)
                      (merge-pathnames "lisp/plecl.lisp" root)
                      (merge-pathnames "lisp/inspect.lisp" root))))
    (dolist (path paths)
      (ok (probe-file path) (namestring path))
      (ok (not (search "uiop:" (with-output-to-string (out)
                                 (with-open-file (in path)
                                   (loop for line = (read-line in nil nil)
                                         while line
                                         do (write-line line out))))))
          (format nil "~a must not contain uiop: reader forms" (file-namestring path))))))
