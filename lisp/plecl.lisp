;;;; Backend runtime — loaded by the PostgreSQL handler into in-process ECL.
;;;; Do not load this into a client image expecting a database connection.

(defpackage #:plecl
  (:use #:cl)
  (:export #:+null+
           #:sql-null-p
           #:query
           #:query-value
           #:execute
           #:compile-function
           #:eval-source
           #:validate
           #:dispatch
           #:dispatch-set
           #:dispatch-trigger
           #:srf-nth
           #:srf-done
           #:window-over
           #:window-over-query
           #:inspect-ref
           #:catalog-packages
           #:catalog-symbols
           #:catalog-functions
           #:catalog-specials
           #:catalog-features
           #:catalog-cache
           #:catalog-image
           #:boot
           #:*trigger*
           #:trigger-new
           #:trigger-old
           #:trigger-get
           #:trigger-op
           #:trigger-name))

(defpackage #:plecl.user
  (:use #:cl #:plecl)
  (:export))

(in-package #:plecl)

(defconstant +null+ '+sql-null+)

(defun sql-null-p (x)
  (eq x +null+))

(defvar *function-cache* (make-hash-table :test 'eql))
(defvar *srf-tables* (make-hash-table :test 'eql))
(defvar *srf-counter* 0)
(defvar *trigger* nil)

(define-condition plecl-error (error)
  ((message :initarg :message :reader plecl-error-message))
  (:report (lambda (c s)
             (format s "plecl: ~a" (plecl-error-message c)))))

(defun read-all (string)
  (let ((*package* (find-package '#:plecl.user))
        (*read-eval* nil))
    (with-input-from-string (in string)
      (loop for form = (read in nil in)
            until (eq form in)
            collect form))))

(defun wrap-body (forms arg-names)
  (let ((body (cond
                ((null forms) nil)
                ((null (cdr forms)) (car forms))
                (t `(progn ,@forms)))))
    (if (and (consp body) (eq (car body) 'lambda))
        body
        `(lambda ,arg-names
           (declare (ignorable ,@arg-names))
           ,body))))

(defun compile-function (source arg-names)
  "Read SOURCE into an interpreted function.

  ECL COMPILE shells out to gcc; that hangs the PostgreSQL backend."
  (let* ((*package* (find-package '#:plecl.user))
         (forms (read-all source))
         (lambda-form (wrap-body forms arg-names)))
    (coerce (eval lambda-form) 'function)))

(defun cached-function (oid xmin source arg-names)
  (let ((ent (gethash oid *function-cache*)))
    (if (and ent (eql (car ent) xmin))
        (cdr ent)
        (let ((fn (compile-function source arg-names)))
          (setf (gethash oid *function-cache*) (cons xmin fn))
          fn))))

(defun safe-call (fn args)
  (let ((*package* (find-package '#:plecl.user)))
    (handler-case (values t (apply fn args))
      (error (c)
        (values nil (princ-to-string c))))))

(defun boxed-ok (value)
  (if (sql-null-p value)
      (cons :null nil)
      (cons :ok value)))

(defun boxed-error (message)
  (cons :error message))

(defun dispatch (oid xmin source arg-names arg-values)
  (handler-case
      (let ((fn (cached-function oid xmin source arg-names)))
        (multiple-value-bind (ok value) (safe-call fn arg-values)
          (if ok
              (boxed-ok value)
              (boxed-error value))))
    (error (c)
      (boxed-error (princ-to-string c)))))

(defun dispatch-set (oid xmin source arg-names arg-values)
  (handler-case
      (let ((fn (cached-function oid xmin source arg-names)))
        (multiple-value-bind (ok value) (safe-call fn arg-values)
          (if ok
              (let* ((list (cond
                             ((sql-null-p value) '())
                             ((listp value) value)
                             (t (list value))))
                     (key (incf *srf-counter*)))
                (setf (gethash key *srf-tables*) (coerce list 'vector))
                (cons :set (cons key (length list))))
              (boxed-error value))))
    (error (c)
      (boxed-error (princ-to-string c)))))

(defun srf-nth (key index)
  (let ((vec (gethash key *srf-tables*)))
    (if (and vec (< index (length vec)))
        (boxed-ok (aref vec index))
        (cons :null nil))))

(defun srf-done (key)
  (remhash key *srf-tables*)
  (cons :ok nil))

(defun trigger-get (key &optional (plist *trigger*))
  (getf plist key))

(defun trigger-new ()
  (trigger-get :new))

(defun trigger-old ()
  (trigger-get :old))

(defun trigger-op ()
  (trigger-get :tg-op))

(defun trigger-name ()
  (trigger-get :tg-name))

(defun dispatch-trigger (oid xmin source arg-names arg-values trigger-plist)
  (declare (ignore arg-names arg-values))
  (let ((*trigger* trigger-plist))
    (handler-case
        (let ((fn (cached-function oid xmin source '())))
          (multiple-value-bind (ok value) (safe-call fn '())
            (cond
              ((not ok) (boxed-error value))
              ((or (eq value :skip) (eq value :null) (sql-null-p value))
               (cons :skip nil))
              ((or (eq value :ok) (eq value t) (eq value :new) (null value))
               (cons :ok nil))
              ((consp value)
               (cons :row value))
              (t (boxed-error "trigger must return :ok, :skip, T, NIL, or an alist")))))
      (error (c)
        (boxed-error (princ-to-string c))))))

(defun eval-source (source)
  (handler-case
      (let* ((*package* (find-package '#:plecl.user))
             (forms (read-all source))
             (value nil))
        (dolist (form forms)
          (setf value (eval form)))
        (boxed-ok value))
    (error (c)
      (boxed-error (princ-to-string c)))))

(defun validate (source arg-names)
  (handler-case
      (progn
        (compile-function source arg-names)
        (cons :ok nil))
    (error (c)
      (boxed-error (princ-to-string c)))))

(defun %spi-query (sql args)
  (declare (ignore sql args))
  (error "plecl: SPI not registered"))

(defun %spi-execute (sql args)
  (declare (ignore sql args))
  (error "plecl: SPI not registered"))

(defun query (sql &rest args)
  (%spi-query sql args))

(defun execute (sql &rest args)
  (%spi-execute sql args))

(defun query-value (sql &rest args)
  (let ((rows (%spi-query sql args)))
    (if (null rows)
        +null+
        (cdar (first rows)))))

(defun boot ()
  (let ((*package* (find-package '#:plecl.user)))
    (cons :ok nil)))

(defun %load-sibling (name)
  (let* ((here (or *load-truename* *compile-file-truename*))
         (path (and here (merge-pathnames name here))))
    (when (and path (probe-file path))
      (load path))))

(%load-sibling "inspect.lisp")
