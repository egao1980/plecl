;;;; Load Lisp source or a packed ASDF tree from a bytea / octet vector.

(in-package #:plecl)

(defparameter +blob-magic+ "PLECLSYS1")

(defvar *runtime-directory* nil)
(defvar *blob-root* nil)
(defvar *loaded-blobs* (make-hash-table :test 'equal))

(defun ensure-bytecode-compiler ()
  "ECL's native COMPILE shells out to gcc and hangs the backend."
  (let ((sym (and (find-package "EXT")
                  (find-symbol "INSTALL-BYTECODES-COMPILER" "EXT"))))
    (when (and sym (fboundp sym))
      (funcall sym)))
  (pushnew :ecl-bytecmp *features*)
  t)

(defun getenv* (name)
  ;; find-symbol: blob.lisp loads before bundled ASDF, so UIOP: is unreadable.
  (flet ((call-if (package symbol)
           (let ((fn (and (find-package package) (find-symbol symbol package))))
             (when (and fn (fboundp fn))
               (ignore-errors (funcall fn name))))))
    (or (call-if "EXT" "GETENV")
        (call-if "UIOP" "GETENV"))))

(defun blob-root ()
  (or *blob-root*
      (let ((tmp (or (getenv* "PLECL_SYSTEM_ROOT")
                     (getenv* "TMPDIR")
                     (getenv* "TMP")
                     "/tmp")))
        (merge-pathnames "plecl-systems/"
                         (pathname (if (and (plusp (length tmp))
                                            (char= (char tmp (1- (length tmp))) #\/))
                                       tmp
                                       (concatenate 'string tmp "/")))))))

(defun octet-vector-p (x)
  (and (vectorp x)
       (plusp (length x))
       (integerp (aref x 0))
       (<= 0 (aref x 0) 255)))

(defun string-to-utf8 (string)
  (let ((out (make-array (length string)
                         :element-type '(unsigned-byte 8)
                         :adjustable t
                         :fill-pointer 0)))
    (loop for c across string
          for code = (char-code c)
          do (cond
               ((< code #x80)
                (vector-push-extend code out))
               ((< code #x800)
                (vector-push-extend (logior #xC0 (ash code -6)) out)
                (vector-push-extend (logior #x80 (logand code #x3F)) out))
               ((< code #x10000)
                (vector-push-extend (logior #xE0 (ash code -12)) out)
                (vector-push-extend (logior #x80 (logand (ash code -6) #x3F)) out)
                (vector-push-extend (logior #x80 (logand code #x3F)) out))
               (t
                (vector-push-extend (logior #xF0 (ash code -18)) out)
                (vector-push-extend (logior #x80 (logand (ash code -12) #x3F)) out)
                (vector-push-extend (logior #x80 (logand (ash code -6) #x3F)) out)
                (vector-push-extend (logior #x80 (logand code #x3F)) out))))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun utf8-to-string (octets)
  (with-output-to-string (s)
    (let ((i 0)
          (n (length octets)))
      (loop while (< i n)
            do (let ((b (aref octets i)))
                 (cond
                   ((< b #x80)
                    (write-char (code-char b) s)
                    (incf i))
                   ((< b #xE0)
                    (write-char (code-char (logior (ash (logand b #x1F) 6)
                                                   (logand (aref octets (1+ i)) #x3F)))
                                s)
                    (incf i 2))
                   ((< b #xF0)
                    (write-char (code-char (logior (ash (logand b #x0F) 12)
                                                   (ash (logand (aref octets (1+ i)) #x3F) 6)
                                                   (logand (aref octets (+ i 2)) #x3F)))
                                s)
                    (incf i 3))
                   (t
                    (write-char (code-char (logior (ash (logand b #x07) 18)
                                                   (ash (logand (aref octets (1+ i)) #x3F) 12)
                                                   (ash (logand (aref octets (+ i 2)) #x3F) 6)
                                                   (logand (aref octets (+ i 3)) #x3F)))
                                s)
                    (incf i 4))))))))

(defun coerce-octets (payload)
  (cond
    ((and (boundp '+null+) (sql-null-p payload))
     (error "plecl blob: payload is null"))
    ((stringp payload)
     (string-to-utf8 payload))
    ((octet-vector-p payload)
     (coerce payload '(simple-array (unsigned-byte 8) (*))))
    ((and (vectorp payload) (zerop (length payload)))
     (make-array 0 :element-type '(unsigned-byte 8)))
    ((or (listp payload) (null payload))
     (coerce (or payload '()) '(simple-array (unsigned-byte 8) (*))))
    (t
     (error "plecl blob: payload must be bytea, string, or octet vector, got ~s"
            (type-of payload)))))

(defun octets-starts-with (octets string)
  (let ((n (length string)))
    (and (>= (length octets) n)
         (loop for i from 0 below n
               always (= (aref octets i) (char-code (char string i)))))))

(defun detect-blob-format (octets format)
  (let ((fmt (if (or (null format)
                     (and (boundp '+null+) (sql-null-p format))
                     (and (stringp format)
                          (or (zerop (length format))
                              (string-equal format "auto"))))
                 :auto
                 (intern (string-upcase (string format)) :keyword))))
    (if (eq fmt :auto)
        (if (octets-starts-with octets +blob-magic+)
            :system
            :lisp)
        fmt)))

(defun safe-relpath (path)
  (let ((s (if (stringp path) path (namestring path))))
    (when (or (zerop (length s))
              (char= (char s 0) #\/)
              (char= (char s 0) #\\)
              (search ".." s))
      (error "plecl blob: illegal path ~s" s))
    s))

(defun append-octets (chunks)
  (let* ((n (reduce #'+ chunks :key #'length))
         (out (make-array n :element-type '(unsigned-byte 8)))
         (o 0))
    (dolist (c chunks out)
      (replace out c :start1 o)
      (incf o (length c)))))

(defun pack-system (files)
  "FILES: list of (relative-path . string-or-octets). Returns (unsigned-byte 8) vector."
  (let ((chunks (list (string-to-utf8 (format nil "~a~%" +blob-magic+)))))
    (dolist (pair files)
      (let* ((path (safe-relpath (car pair)))
             (data (if (stringp (cdr pair))
                       (string-to-utf8 (cdr pair))
                       (coerce-octets (cdr pair))))
             (hdr (string-to-utf8 (format nil "FILE ~d ~a~%" (length data) path))))
        (push hdr chunks)
        (push data chunks)))
    (append-octets (nreverse chunks))))

(defun read-line-octets (octets start)
  (let ((end (position 10 octets :start start)))
    (unless end
      (error "plecl blob: truncated header"))
    (values (utf8-to-string (subseq octets start end)) (1+ end))))

(defun unpack-system (payload directory)
  "Write a packed system into DIRECTORY. Return written pathnames."
  (let* ((octets (coerce-octets payload))
         (written '()))
    (unless (octets-starts-with octets +blob-magic+)
      (error "plecl blob: not a packed system"))
    (ensure-directories-exist (pathname-as-directory directory))
    (multiple-value-bind (magic pos) (read-line-octets octets 0)
      (declare (ignore magic))
      (loop while (< pos (length octets))
            do (multiple-value-bind (line next) (read-line-octets octets pos)
                 (unless (and (>= (length line) 5) (string= line "FILE " :end1 5))
                   (error "plecl blob: bad entry ~s" line))
                 (let* ((rest (subseq line 5))
                        (spc (position #\Space rest)))
                   (unless spc
                     (error "plecl blob: bad FILE header ~s" line))
                   (let* ((size (parse-integer rest :end spc))
                          (rel (safe-relpath (subseq rest (1+ spc))))
                          (dest (merge-pathnames rel (pathname-as-directory directory))))
                     (when (> (+ next size) (length octets))
                       (error "plecl blob: truncated file ~s" rel))
                     (ensure-directories-exist dest)
                     (with-open-file (out dest :direction :output
                                          :if-exists :supersede
                                          :element-type '(unsigned-byte 8))
                       (write-sequence octets out :start next :end (+ next size)))
                     (push dest written)
                     (setf pos (+ next size)))))))
    (nreverse written)))

(defun pathname-as-directory (path)
  (let ((p (pathname path)))
    (if (pathname-name p)
        (make-pathname :defaults p
                       :name nil
                       :type nil
                       :directory (append (or (pathname-directory p) '(:relative))
                                          (list (file-namestring p))))
        p)))

(defun load-source-string (string)
  (let ((*package* (or (find-package '#:plecl.user) *package*))
        (*read-eval* nil)
        (last nil))
    (with-input-from-string (in string)
      (loop for form = (read in nil in)
            until (eq form in)
            do (setf last (eval form))))
    last))

(defun asdf-version-string ()
  (ensure-asdf)
  (let* ((pkg (find-package :asdf))
         (fn (and pkg (find-symbol "ASDF-VERSION" pkg))))
    (if (and fn (fboundp fn))
        (princ-to-string (funcall fn))
        +null+)))

(defun load-lisp-source-file (path)
  "EVAL forms from PATH. Do not LOAD — ECL LOAD compile-files and will
   shell out to gcc (native) or blow the backend (huge bytecode compile)."
  (ensure-bytecode-compiler)
  (with-open-file (in path)
    (let ((*package* (or (find-package :cl-user) *package*))
          (*read-eval* t)
          (*load-truename* (ignore-errors (truename path)))
          (*load-pathname* path)
          (*compile-verbose* nil)
          (*compile-print* nil)
          (*load-verbose* nil)
          (*load-print* nil))
      (loop for form = (read in nil in)
            until (eq form in)
            do (eval form)))))

(defun load-bundled-asdf ()
  "Install the bytecode compiler, then eval vendor/asdf.lisp (3.3.7)."
  (ensure-bytecode-compiler)
  (let ((path (or (and *runtime-directory* (merge-pathnames "asdf.lisp" *runtime-directory*))
                  (let ((here (or *load-truename* *compile-file-truename*)))
                    (and here (merge-pathnames "asdf.lisp"
                                               (merge-pathnames "../vendor/" here)))))))
    (cond
      ((and path (probe-file path))
       (load-lisp-source-file path)
       (let ((rehook (find-symbol "INSTALL-DEBUGGER-HOOKS" "PLECL")))
         (when (and rehook (fboundp rehook))
           (funcall rehook)))
       :bundled)
      ((find-package :asdf)
       :preloaded)
      (t
       (ignore-errors (require :asdf))
       (if (find-package :asdf) :required :missing)))))

(defun ensure-asdf ()
  (or (find-package :asdf)
      (progn
        (load-bundled-asdf)
        (find-package :asdf))))

(defun asd-files (directory)
  (let ((dir (pathname-as-directory directory)))
    (append (directory (merge-pathnames "*.asd" dir))
            (directory (make-pathname :defaults dir :name :wild :type "asd")))))

(defun lisp-files (directory)
  (let ((dir (pathname-as-directory directory)))
    (sort (remove-duplicates
           (append (directory (merge-pathnames "*.lisp" dir))
                   (directory (make-pathname :defaults dir :name :wild :type "lisp")))
           :test #'equal)
          #'string< :key #'namestring)))

(defun eval-lisp-file (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((buf (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence buf in)
      (load-source-string (utf8-to-string buf)))))

(defun load-unpacked-system (directory &optional name written)
  "Eval .lisp files. Prefer WRITTEN (pack order) so :serial asd files load
   pkg then body. Do not asdf:load-system — compile-file SIGSEGVs the
   backend (Homebrew ECL 26, seen in 90_blob)."
  (ensure-bytecode-compiler)
  (let* ((dir (pathname-as-directory directory))
         (asds (remove-duplicates (asd-files dir) :test #'equal))
         (lisps (or (remove-if-not (lambda (p)
                                     (equalp (pathname-type p) "lisp"))
                                   written)
                    (lisp-files dir))))
    (dolist (path lisps)
      (eval-lisp-file path))
    (or name
        (and asds (pathname-name (first asds)))
        "lisp")))

(defun record-loaded (name format dir)
  (setf (gethash name *loaded-blobs*)
        (list :name name :format format :directory (and dir (namestring dir))))
  name)

(defun load-blob (payload &optional (name "blob") (format "auto"))
  "Load PAYLOAD (bytea / octets / string). FORMAT: auto | lisp | system."
  (when (or (null name) (and (boundp '+null+) (sql-null-p name))
            (and (stringp name) (zerop (length name))))
    (setf name "blob"))
  (let* ((octets (coerce-octets payload))
         (fmt (detect-blob-format octets format)))
    (ecase fmt
      ((:lisp :source)
       (load-source-string (utf8-to-string octets))
       (record-loaded (string name) :lisp nil)
       (format nil "loaded:~a" name))
      ((:system :tree :asd)
       (let ((dir (merge-pathnames (concatenate 'string (safe-relpath (string name)) "/")
                                   (blob-root))))
         (let* ((written (unpack-system octets dir))
                (sys (load-unpacked-system dir name written)))
           (record-loaded (string sys) :system dir)
           (format nil "loaded:~a" sys)))))))

(defun load-system (name)
  "Load NAME from lisp.systems via SPI."
  (when (or (null name) (and (boundp '+null+) (sql-null-p name)))
    (error "plecl blob: system name is required"))
  (unless (fboundp 'query)
    (error "plecl blob: QUERY is not available outside the backend"))
  (let ((rows (funcall (symbol-function 'query)
                       "SELECT payload, format FROM lisp.systems WHERE name = $1"
                       name)))
    (when (null rows)
      (error "plecl blob: no system named ~s" name))
    (let* ((row (first rows))
           (payload (cdr (or (assoc :payload row) (assoc :PAYLOAD row))))
           (format (cdr (or (assoc :format row) (assoc :FORMAT row))))
           (status (load-blob payload name format)))
      (ignore-errors
        (funcall (symbol-function 'execute)
                 "UPDATE lisp.systems SET loaded_at = clock_timestamp() WHERE name = $1"
                 name))
      status)))

(defun store-system (name payload &optional (format "auto"))
  "UPSERT lisp.systems then load."
  (when (or (null name) (and (boundp '+null+) (sql-null-p name)))
    (error "plecl blob: system name is required"))
  (unless (fboundp 'execute)
    (error "plecl blob: EXECUTE is not available outside the backend"))
  (funcall (symbol-function 'execute)
           "INSERT INTO lisp.systems(name, payload, format)
            VALUES ($1, $2, $3)
            ON CONFLICT (name) DO UPDATE
              SET payload = EXCLUDED.payload,
                  format = EXCLUDED.format,
                  loaded_at = NULL"
           name (coerce-octets payload)
           (if (or (null format) (and (boundp '+null+) (sql-null-p format)))
               "auto"
               (string format)))
  (load-system name))

(defun catalog-loaded ()
  (let ((out '()))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push (list (cons :name (getf v :name))
                           (cons :format (string-downcase (princ-to-string (getf v :format))))
                           (cons :directory (getf v :directory)))
                     out))
             *loaded-blobs*)
    (sort out #'string< :key (lambda (row) (cdr (assoc :name row))))))

(eval-when (:load-toplevel :execute)
  (export '(pack-system
            unpack-system
            load-blob
            load-system
            store-system
            catalog-loaded
            ensure-bytecode-compiler
            load-bundled-asdf
            asdf-version-string)
          :plecl))
