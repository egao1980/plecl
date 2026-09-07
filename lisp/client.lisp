(in-package #:plecl)

(define-condition plecl-error (error)
  ((message :initarg :message :reader plecl-error-message))
  (:report (lambda (c s)
             (format s "plecl: ~a" (plecl-error-message c)))))

(defun dollar-quote (source &optional (tag "plecl"))
  "Wrap SOURCE in a PostgreSQL dollar-quote that does not appear in SOURCE."
  (check-type source string)
  (check-type tag string)
  (labels ((try (candidate)
             (let ((delim (format nil "$~a$" candidate)))
               (if (search delim source)
                   (try (format nil "~a~d" candidate (random 10000)))
                   (concatenate 'string delim source delim)))))
    (try tag)))

(defun function-sql (name params returns source &key (language :plecl) replace)
  "Emit CREATE FUNCTION ... LANGUAGE plecl AS $plecl$...$plecl$."
  (check-type source string)
  (with-output-to-string (s)
    (write-string "CREATE " s)
    (when replace (write-string "OR REPLACE " s))
    (format s "FUNCTION ~a(~{~a~^, ~}) RETURNS ~a LANGUAGE ~a "
            name params returns
            (string-downcase (string language)))
    (write-string (dollar-quote source) s)))
