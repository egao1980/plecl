;;;; Bytecode-compile vendor/asdf.lisp → asdf.fasc
;;;;
;;;; ASDF 3.3.7 has #.(case +max-character-type-index+ …) at read time.
;;;; ECL 26's bytecodes compile-file does not eval the preceding
;;;; defparameter before reading the next form, so compile-file alone
;;;; dies: "+MAX-CHARACTER-TYPE-INDEX+ is unbound". LOAD first.

(ext:install-bytecodes-compiler)

(defun getenv* (name)
  (let ((fn (and (find-package "EXT") (find-symbol "GETENV" "EXT"))))
    (when (and fn (fboundp fn))
      (funcall fn name))))

(let* ((in (pathname (or (getenv* "ASDF_LISP") "vendor/asdf.lisp")))
       (out (pathname (or (getenv* "ASDF_FASC") "asdf.fasc")))
       (*compile-verbose* nil)
       (*load-verbose* nil))
  (unless (probe-file in)
    (format *error-output* "compile-asdf: missing ~a~%" in)
    (ext:quit 1))
  (load in)
  (let ((r (compile-file in :output-file out)))
    (unless (and r (probe-file r))
      (format *error-output* "compile-asdf: compile-file failed~%")
      (ext:quit 1)))
  (ext:quit 0))
