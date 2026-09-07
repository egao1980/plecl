-- Demo: a windowed aggregation created entirely from SQL (LANGUAGE plecl).
-- Not part of the extension — this is the "we can write aggregates in SQL" proof.

CREATE TABLE demo_sales (
  store text NOT NULL,
  day integer NOT NULL,
  amount double precision NOT NULL
);

INSERT INTO demo_sales (store, day, amount) VALUES
  ('east', 1, 10),
  ('east', 2, 20),
  ('east', 3, 30),
  ('east', 4, 40),
  ('west', 1, 5),
  ('west', 2, 15);

CREATE TYPE demo_sales_window AS (
  store text,
  day integer,
  amount double precision,
  row_number integer,
  rank integer,
  dense_rank integer,
  running_sum double precision,
  frame_avg double precision,
  lag_amount double precision,
  zscore double precision,
  share double precision
);

CREATE FUNCTION demo_sales_window(frame_preceding integer DEFAULT 1)
RETURNS SETOF demo_sales_window
LANGUAGE plecl
AS $plecl$
(let* ((prec (cond
               ((or (plecl:sql-null-p frame_preceding) (minusp frame_preceding))
                most-positive-fixnum)
               (t frame_preceding)))
       (rows (plecl:query "SELECT store, day, amount FROM demo_sales ORDER BY store, day"))
       (get (lambda (row k) (cdr (assoc k row))))
       (groups (make-hash-table :test 'equal))
       (order '()))
  (dolist (row rows)
    (let ((store (funcall get row :store)))
      (unless (gethash store groups)
        (push store order))
      (push row (gethash store groups))))
  (mapcan
   (lambda (store)
     (let* ((part (sort (nreverse (copy-list (gethash store groups)))
                        #'< :key (lambda (r) (funcall get r :day))))
            (n (length part))
            (xs (mapcar (lambda (r) (float (funcall get r :amount) 1.0d0)) part))
            (total (reduce #'+ xs))
            (mean (/ total n))
            (sd (when (> n 1)
                  (sqrt (/ (reduce #'+ xs
                                   :key (lambda (x) (expt (- x mean) 2))
                                   :initial-value 0.0d0)
                           (float (1- n) 1.0d0))))))
       (loop for i from 0 below n
             for x = (nth i xs)
             for lo = (max 0 (- i prec))
             for frame = (subseq xs lo (1+ i))
             for rank = (1+ (count-if (lambda (y) (< y x)) xs))
             for dense = (1+ (length (remove-duplicates
                                      (remove-if (lambda (y) (>= y x)) xs)
                                      :test #'=)))
             collect (list (cons :store store)
                           (cons :day (funcall get (nth i part) :day))
                           (cons :amount x)
                           (cons :row_number (1+ i))
                           (cons :rank rank)
                           (cons :dense_rank dense)
                           (cons :running_sum (reduce #'+ xs :end (1+ i)))
                           (cons :frame_avg (/ (reduce #'+ frame) (length frame)))
                           (cons :lag_amount (and (plusp i) (nth (1- i) xs)))
                           (cons :zscore (and sd (plusp sd) (/ (- x mean) sd)))
                           (cons :share (/ x total))))))
   (nreverse order)))
$plecl$;

SELECT store, day, amount, row_number, rank, dense_rank,
       running_sum, frame_avg, lag_amount, share
FROM demo_sales_window(1)
ORDER BY store, day;
