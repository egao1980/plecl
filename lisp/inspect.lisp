;;;; Structured inspector over the in-process ECL image.
;;;; Backend loads this after plecl.lisp; client ASDF loads it for unit tests.

(in-package #:plecl)

(defvar *function-cache*)

(defparameter *inspect-print-limit* 512)
(defparameter *inspect-max-children* 64)

(defun printed (x &optional (limit *inspect-print-limit*))
  (let ((s (with-output-to-string (out)
             (write x :stream out :pretty nil :circle t :length 16 :level 4))))
    (if (and limit (> (length s) limit))
        (concatenate 'string (subseq s 0 limit) "...")
        s)))

(defun type-string (x)
  (printed (type-of x) 120))

(defun inspect-pair (key value)
  (cons key value))

(defun inspect-row (path kind obj &optional length)
  (let ((row (list (inspect-pair :path path)
                   (inspect-pair :kind kind)
                   (inspect-pair :type (type-string obj))
                   (inspect-pair :value (printed obj)))))
    (if length
        (nconc row (list (inspect-pair :length length)))
        row)))

(defun identity-object-p (x)
  (or (consp x)
      (and (arrayp x) (not (stringp x)))
      (hash-table-p x)
      (typep x 'standard-object)
      (typep x 'structure-object)
      (packagep x)))

(defun parse-symbol-ref (s)
  (let ((dcolon (search "::" s)))
    (if dcolon
        (values (subseq s 0 dcolon) (subseq s (+ dcolon 2)))
        (let ((colon (position #\: s)))
          (if colon
              (values (subseq s 0 colon) (subseq s (1+ colon)))
              (values nil s))))))

(defun find-named-package (name)
  (and name (plusp (length name)) (find-package (string-upcase name))))

(defun find-named-symbol (name &optional package)
  (let ((n (string-upcase name)))
    (if package
        (find-symbol n package)
        (dolist (pkg (list (find-package '#:plecl.user)
                           (find-package '#:plecl)
                           (find-package '#:cl))
                 nil)
          (when pkg
            (let ((sym (find-symbol n pkg)))
              (when sym
                (return sym))))))))

(defun resolve-ref (ref)
  (when (or (null ref) (and (boundp '+null+) (sql-null-p ref)))
    (error "lisp inspect: ref is required"))
  (let ((s (string-trim '(#\Space #\Tab #\Newline) (if (stringp ref)
                                                      ref
                                                      (princ-to-string ref)))))
    (cond
      ((zerop (length s))
       (error "lisp inspect: empty ref"))
      ((char= (char s 0) #\()
       (let ((*package* (or (find-package '#:plecl.user) *package*))
             (*read-eval* nil))
         (eval (read-from-string s))))
      (t
       (multiple-value-bind (pkg-name sym-name) (parse-symbol-ref s)
         (let ((pkg (and pkg-name
                         (or (find-named-package pkg-name)
                             (error "lisp inspect: no package ~s" pkg-name)))))
           (cond
             ((and pkg-name (zerop (length (string-trim '(#\Space) sym-name))))
              pkg)
             ((and (not pkg-name) (find-named-package s)))
             ((find-named-symbol sym-name pkg))
             (t
              (error "lisp inspect: cannot resolve ~s" s)))))))))

(defun child-path (parent label)
  (if (or (null parent) (string= parent ""))
      label
      (concatenate 'string parent "." label)))

(defun walk-limited (items parent-path kind-fn value-fn depth visited emit)
  (let ((n 0))
    (dolist (item items)
      (when (>= n *inspect-max-children*)
        (funcall emit (inspect-row (child-path parent-path "...") "truncated" (- (length items) n)))
        (return))
      (inspect-walk (funcall value-fn item)
                    (child-path parent-path (funcall kind-fn item n))
                    (1- depth) visited emit)
      (incf n))))

(defun instance-slot-names (obj)
  (ignore-errors
    (mapcar (lambda (slot)
              (or (ignore-errors (funcall (find-symbol "SLOT-DEFINITION-NAME" "CLOS") slot))
                  (ignore-errors (funcall (find-symbol "SLOT-DEFINITION-NAME" "SB-MOP") slot))
                  slot))
            (let ((class-slots (or (and (find-package "CLOS")
                                        (find-symbol "CLASS-SLOTS" "CLOS"))
                                   (and (find-package "SB-MOP")
                                        (find-symbol "CLASS-SLOTS" "SB-MOP")))))
              (when class-slots
                (funcall class-slots (class-of obj)))))))

(defun inspect-walk (obj path depth visited emit)
  (when (and (identity-object-p obj) (gethash obj visited))
    (funcall emit (inspect-row path "cycle" obj))
    (return-from inspect-walk))
  (when (identity-object-p obj)
    (setf (gethash obj visited) t))
  (cond
    ((packagep obj)
     (funcall emit (inspect-row path "package" obj (length (package-name obj))))
     (when (plusp depth)
       (funcall emit (inspect-row (child-path path "name") "slot" (package-name obj)))
       (dolist (nick (package-nicknames obj))
         (funcall emit (inspect-row (child-path path "nickname") "slot" nick)))
       (inspect-walk (package-use-list obj) (child-path path "use") (1- depth) visited emit)))
    ((symbolp obj)
     (funcall emit (inspect-row path "symbol" obj))
     (when (plusp depth)
       (when (symbol-package obj)
         (funcall emit (inspect-row (child-path path "package") "slot"
                                    (package-name (symbol-package obj)))))
       (funcall emit (inspect-row (child-path path "name") "slot" (symbol-name obj)))
       (when (boundp obj)
         (inspect-walk (symbol-value obj) (child-path path "value") (1- depth) visited emit))
       (when (fboundp obj)
         (inspect-walk (symbol-function obj) (child-path path "function") (1- depth) visited emit))
       (when (symbol-plist obj)
         (inspect-walk (symbol-plist obj) (child-path path "plist") (1- depth) visited emit))))
    ((consp obj)
     (let ((len (ignore-errors (list-length obj))))
       (funcall emit (inspect-row path (if (and len (null (cdr (last obj)))) "list" "cons")
                                  obj len))
       (when (plusp depth)
         (if (and len (null (cdr (last obj))))
             (walk-limited obj path
                           (lambda (item i)
                             (declare (ignore item))
                             (format nil "[~d]" i))
                           (lambda (item) item)
                           depth visited emit)
             (progn
               (inspect-walk (car obj) (child-path path "car") (1- depth) visited emit)
               (inspect-walk (cdr obj) (child-path path "cdr") (1- depth) visited emit))))))
    ((and (arrayp obj) (not (stringp obj)))
     (funcall emit (inspect-row path "array" obj (array-total-size obj)))
     (when (plusp depth)
       (loop for i from 0 below (min (array-total-size obj) *inspect-max-children*)
             do (inspect-walk (row-major-aref obj i)
                              (child-path path (format nil "[~d]" i))
                              (1- depth) visited emit))))
    ((hash-table-p obj)
     (funcall emit (inspect-row path "hash-table" obj (hash-table-count obj)))
     (when (plusp depth)
       (let ((n 0))
         (maphash (lambda (k v)
                    (when (>= n *inspect-max-children*)
                      (funcall emit (inspect-row (child-path path "...") "truncated"
                                                 (- (hash-table-count obj) n)))
                      (return-from inspect-walk))
                    (inspect-walk v (child-path path (printed k 40))
                                  (1- depth) visited emit)
                    (incf n))
                  obj))))
    ((or (typep obj 'standard-object) (typep obj 'structure-object))
     (funcall emit (inspect-row path "object" obj))
     (when (plusp depth)
       (funcall emit (inspect-row (child-path path "class") "slot"
                                  (class-name (class-of obj))))
       (dolist (slot (or (instance-slot-names obj) '()))
         (when (and (symbolp slot) (slot-boundp obj slot))
           (inspect-walk (slot-value obj slot)
                         (child-path path (string-downcase (symbol-name slot)))
                         (1- depth) visited emit)))))
    ((functionp obj)
     (funcall emit (inspect-row path "function" obj)))
    (t
     (funcall emit (inspect-row path "atom" obj)))))

(defun inspect-ref (ref &optional (depth 3))
  "Walk REF (symbol, package, or a *read-eval*-nil form) as inspector rows."
  (let ((depth (if (and (boundp '+null+) (sql-null-p depth)) 3 depth))
        (rows '()))
    (unless (integerp depth)
      (setf depth (or (ignore-errors (round depth)) 3)))
    (inspect-walk (resolve-ref ref) "" depth (make-hash-table :test 'eq)
                  (lambda (row) (push row rows)))
    (nreverse rows)))

(defun package-symbol-counts (pkg)
  (let ((external 0)
        (internal 0))
    (do-external-symbols (s pkg)
      (incf external))
    (do-symbols (s pkg)
      (when (eq (symbol-package s) pkg)
        (multiple-value-bind (sym status) (find-symbol (symbol-name s) pkg)
          (declare (ignore sym))
          (when (eq status :internal)
            (incf internal)))))
    (values external internal)))

(defun catalog-packages ()
  (mapcar
   (lambda (pkg)
     (multiple-value-bind (external internal) (package-symbol-counts pkg)
       (list (inspect-pair :name (package-name pkg))
             (inspect-pair :nicknames (mapcar #'identity (package-nicknames pkg)))
             (inspect-pair :n_external external)
             (inspect-pair :n_internal internal)
             (inspect-pair :used (mapcar #'package-name (package-use-list pkg)))
             (inspect-pair :used_by (mapcar #'package-name (package-used-by-list pkg))))))
   (sort (copy-list (list-all-packages)) #'string< :key #'package-name)))

(defun interesting-packages (package-name)
  (cond
    ((and package-name
          (or (and (boundp '+null+) (sql-null-p package-name))
              (and (stringp package-name) (zerop (length (string-trim '(#\Space) package-name))))))
     (interesting-packages nil))
    (package-name
     (list (or (find-named-package package-name)
               (error "lisp inspect: no package ~s" package-name))))
    (t
     (remove nil (list (find-package '#:plecl)
                       (find-package '#:plecl.user)
                       (find-package '#:cl-user))))))

(defun symbol-accessibility (sym pkg)
  (nth-value 1 (find-symbol (symbol-name sym) pkg)))

(defun function-kind (sym)
  (cond
    ((special-operator-p sym) "special")
    ((macro-function sym) "macro")
    ((fboundp sym) "function")
    (t nil)))

(defun catalog-symbols (&optional package-name)
  (let ((out '()))
    (dolist (pkg (interesting-packages package-name) (nreverse out))
      (do-symbols (sym pkg)
        (when (eq (symbol-package sym) pkg)
          (push (list (inspect-pair :package (package-name pkg))
                      (inspect-pair :name (symbol-name sym))
                      (inspect-pair :accessibility
                                    (string-downcase
                                     (princ-to-string (or (symbol-accessibility sym pkg) :internal))))
                      (inspect-pair :boundp (and (boundp sym) t))
                      (inspect-pair :fboundp (and (fboundp sym) t))
                      (inspect-pair :value (and (boundp sym) (printed (symbol-value sym) 200)))
                      (inspect-pair :function_type (function-kind sym))
                      (inspect-pair :documentation
                                    (or (documentation sym 'function)
                                        (documentation sym 'variable))))
                out))))))

(defun catalog-functions (&optional package-name)
  (remove-if-not (lambda (row) (cdr (assoc :fboundp row)))
                 (catalog-symbols package-name)))

(defun catalog-specials (&optional package-name)
  (remove-if-not (lambda (row) (cdr (assoc :boundp row)))
                 (catalog-symbols package-name)))

(defun catalog-features ()
  (mapcar (lambda (f)
            (list (inspect-pair :feature
                                (if (keywordp f)
                                    (symbol-name f)
                                    (printed f 80)))))
          (copy-list *features*)))

(defun catalog-cache ()
  (if (and (boundp '*function-cache*) (hash-table-p *function-cache*))
      (let ((out '()))
        (maphash (lambda (oid ent)
                   (push (list (inspect-pair :oid oid)
                               (inspect-pair :xmin (if (consp ent) (car ent) nil))
                               (inspect-pair :boundp t))
                         out))
                 *function-cache*)
        (sort out #'< :key (lambda (row) (or (cdr (assoc :oid row)) 0))))
      '()))

(defun catalog-image ()
  (list (list (inspect-pair :implementation (lisp-implementation-type))
              (inspect-pair :version (lisp-implementation-version))
              (inspect-pair :n_packages (length (list-all-packages)))
              (inspect-pair :n_cached (if (and (boundp '*function-cache*)
                                               (hash-table-p *function-cache*))
                                          (hash-table-count *function-cache*)
                                          0))
              (inspect-pair :n_features (length *features*)))))

(eval-when (:load-toplevel :execute)
  (export '(inspect-ref
            catalog-packages
            catalog-symbols
            catalog-functions
            catalog-specials
            catalog-features
            catalog-cache
            catalog-image)
          :plecl))
