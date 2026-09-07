-- Complex LANGUAGE plecl analytics. SQL aggregates; Lisp runs the algorithms.
-- Not extension primitives — load this file after CREATE EXTENSION + lineitem.

DROP FUNCTION IF EXISTS tpch_interval_schedule(integer, integer, integer);
DROP FUNCTION IF EXISTS tpch_changepoints(integer, integer, double precision);
DROP FUNCTION IF EXISTS tpch_supplier_kmeans(integer, integer);
DROP FUNCTION IF EXISTS tpch_holt_winters(integer, integer, integer);
DROP FUNCTION IF EXISTS tpch_late_viterbi(integer);
DROP TYPE IF EXISTS tpch_interval_pick;
DROP TYPE IF EXISTS tpch_segment;
DROP TYPE IF EXISTS tpch_cluster;
DROP TYPE IF EXISTS tpch_forecast;
DROP TYPE IF EXISTS tpch_regime;

CREATE TYPE tpch_interval_pick AS (
  linenumber integer,
  orderkey bigint,
  start_day integer,
  end_day integer,
  revenue double precision,
  taken boolean
);

CREATE TYPE tpch_segment AS (
  seg integer,
  start_day integer,
  end_day integer,
  n integer,
  mean_rev double precision,
  rss double precision
);

CREATE TYPE tpch_cluster AS (
  supplier integer,
  cluster integer,
  discount double precision,
  delay double precision,
  return_rate double precision,
  log_rev double precision
);

CREATE TYPE tpch_forecast AS (
  week integer,
  actual double precision,
  fitted double precision,
  yhat double precision,
  lo double precision,
  hi double precision
);

CREATE TYPE tpch_regime AS (
  day integer,
  late_frac double precision,
  state text,
  logp double precision
);

DO LANGUAGE plecl $plecl$
(progn
  (defun tpch-get (row k)
    (let ((pair (assoc k row)))
      (unless pair
        (error "missing ~s in ~s" k row))
      (cdr pair)))

  (defun tpch-num (x)
    (cond ((plecl:sql-null-p x) 0.0d0)
          ((realp x) (float x 1.0d0))
          ((stringp x) (let ((*read-eval* nil)) (float (read-from-string x) 1.0d0)))
          (t (error "not a number: ~s" x))))

  (defun tpch-int (x)
    (round (tpch-num x)))

  (defun tpch-alist (&rest ks)
    (loop for (k v) on ks by #'cddr
          collect (cons k (if v v plecl:+null+))))

  (defun prefix-sums (xs)
    (let* ((n (length xs))
           (s (make-array (1+ n) :initial-element 0.0d0))
           (q (make-array (1+ n) :initial-element 0.0d0)))
      (loop for i from 0 below n
            for x = (aref xs i)
            do (setf (aref s (1+ i)) (+ (aref s i) x)
                     (aref q (1+ i)) (+ (aref q i) (* x x))))
      (values s q)))

  (defun range-n (lo hi)
    (- hi lo))

  (defun range-sum (ps lo hi)
    (- (aref ps hi) (aref ps lo)))

  (defun range-rss (ps qs lo hi)
    (let* ((n (range-n lo hi))
           (s (range-sum ps lo hi)))
      (if (zerop n)
          0.0d0
          (- (range-sum qs lo hi) (/ (* s s) n)))))

  (defun range-mean (ps lo hi)
    (let ((n (range-n lo hi)))
      (if (zerop n) 0.0d0 (/ (range-sum ps lo hi) n))))

  (defun binary-search-pred (ends start)
    (let ((lo 0)
          (hi (1- (length ends)))
          (ans -1))
      (loop while (and (>= hi 0) (<= lo hi))
            do (let ((mid (floor (+ lo hi) 2)))
                 (if (<= (aref ends mid) start)
                     (setf ans mid lo (1+ mid))
                     (setf hi (1- mid)))))
      ans))

  (defun weighted-interval (items)
    "items: vector of (id order start end weight). Max-weight non-overlapping, sort by end."
    (let* ((v (sort (copy-seq items) #'< :key (lambda (it) (nth 3 it))))
           (n (length v)))
      (when (zerop n)
        (return-from weighted-interval (values #() #())))
      (let ((ends (map 'vector (lambda (it) (nth 3 it)) v))
            (dp (make-array n :initial-element 0.0d0))
            (take (make-array n :initial-element nil))
            (pred (make-array n :initial-element -1)))
        (loop for i from 0 below n
              for start = (nth 2 (aref v i))
              for w = (nth 4 (aref v i))
              for p = (binary-search-pred ends start)
              for skip = (if (plusp i) (aref dp (1- i)) 0.0d0)
              for use = (+ w (if (>= p 0) (aref dp p) 0.0d0))
              do (setf (aref pred i) p)
                 (if (>= use skip)
                     (setf (aref dp i) use (aref take i) t)
                     (setf (aref dp i) skip (aref take i) nil)))
        (let ((chosen (make-array n :initial-element nil))
              (i (1- n)))
          (loop while (>= i 0)
                do (if (aref take i)
                       (progn (setf (aref chosen i) t)
                              (setf i (aref pred i)))
                       (decf i)))
          (values v chosen)))))

  (defun binary-segment (xs days min-size penalty)
    (let* ((n (length xs))
           (segs '()))
      (when (< n (* 2 min-size))
        (return-from binary-segment
          (list (list 0 n (if (plusp n)
                              (/ (reduce #'+ xs) n)
                              0.0d0)
                      0.0d0))))
      (multiple-value-bind (ps qs) (prefix-sums xs)
        (labels ((rec (lo hi)
                   (let ((best nil)
                         (best-gain 0.0d0)
                         (full (range-rss ps qs lo hi)))
                     (loop for mid from (+ lo min-size) to (- hi min-size)
                           for gain = (- full (+ (range-rss ps qs lo mid)
                                                 (range-rss ps qs mid hi)))
                           when (> gain best-gain)
                             do (setf best mid best-gain gain))
                     (if (and best (> best-gain penalty))
                         (progn (rec lo best) (rec best hi))
                         (push (list lo hi (range-mean ps lo hi)
                                     (range-rss ps qs lo hi))
                               segs)))))
          (rec 0 n)))
      (mapcar (lambda (s)
                (list (aref days (first s))
                      (aref days (1- (second s)))
                      (- (second s) (first s))
                      (third s)
                      (fourth s)))
              (sort segs #'< :key #'first))))

  (defun standardize-cols (pts nfeat)
    (let* ((n (length pts))
           (mean (make-array nfeat :initial-element 0.0d0))
           (sd (make-array nfeat :initial-element 1.0d0)))
      (when (zerop n)
        (return-from standardize-cols (values pts mean sd)))
      (loop for p across pts
            do (loop for j from 0 below nfeat
                     do (incf (aref mean j) (aref p (1+ j)))))
      (loop for j from 0 below nfeat
            do (setf (aref mean j) (/ (aref mean j) n)))
      (loop for p across pts
            do (loop for j from 0 below nfeat
                     for d = (- (aref p (1+ j)) (aref mean j))
                     do (incf (aref sd j) (* d d))))
      (loop for j from 0 below nfeat
            do (setf (aref sd j)
                     (let ((v (/ (aref sd j) (max 1 (1- n)))))
                       (if (> v 1d-12) (sqrt v) 1.0d0))))
      (loop for p across pts
            do (loop for j from 0 below nfeat
                     do (setf (aref p (1+ j))
                              (/ (- (aref p (1+ j)) (aref mean j))
                                 (aref sd j)))))
      (values pts mean sd)))

  (defun kmeans-pp (pts k nfeat)
    (let* ((n (length pts))
           (k (min k n))
           (cent (make-array k))
           (first (random n)))
      (setf (aref cent 0) (copy-seq (aref pts first)))
      (loop for c from 1 below k
            for dist = (make-array n :initial-element 0.0d0)
            for tot = 0.0d0
            do (loop for i from 0 below n
                     for p = (aref pts i)
                     for best = most-positive-double-float
                     do (loop for j from 0 below c
                              for d = (loop for f from 1 to nfeat
                                            for diff = (- (aref p f)
                                                          (aref (aref cent j) f))
                                            sum (* diff diff))
                              do (setf best (min best d)))
                        (setf (aref dist i) best)
                        (incf tot best))
               (let ((r (* (random 1.0d0) tot))
                     (acc 0.0d0)
                     (pick 0))
                 (loop for i from 0 below n
                       do (incf acc (aref dist i))
                          (when (>= acc r)
                            (setf pick i)
                            (return)))
                 (setf (aref cent c) (copy-seq (aref pts pick))))))
      cent))

  (defun kmeans (pts k n-iter nfeat)
    (let* ((n (length pts))
           (k (max 1 (min k n)))
           (cent (kmeans-pp pts k nfeat))
           (assign (make-array n :initial-element 0)))
      (dotimes (_ n-iter)
        (loop for i from 0 below n
              for p = (aref pts i)
              for best = 0
              for best-d = most-positive-double-float
              do (loop for j from 0 below k
                       for d = (loop for f from 1 to nfeat
                                     for diff = (- (aref p f) (aref (aref cent j) f))
                                     sum (* diff diff))
                       when (< d best-d)
                         do (setf best j best-d d))
                 (setf (aref assign i) best))
        (let ((sum (make-array k))
              (cnt (make-array k :initial-element 0)))
          (loop for j from 0 below k
                do (setf (aref sum j) (make-array (1+ nfeat) :initial-element 0.0d0)))
          (loop for i from 0 below n
                for j = (aref assign i)
                do (incf (aref cnt j))
                   (loop for f from 1 to nfeat
                         do (incf (aref (aref sum j) f) (aref (aref pts i) f))))
          (loop for j from 0 below k
                do (if (plusp (aref cnt j))
                       (loop for f from 1 to nfeat
                             do (setf (aref (aref cent j) f)
                                      (/ (aref (aref sum j) f) (aref cnt j))))
                       (setf (aref cent j)
                             (copy-seq (aref pts (random n))))))))
      (values assign cent)))

  (defun holt-winters (ys m alpha beta gamma)
    (let* ((n (length ys))
           (level (make-array n :initial-element 0.0d0))
           (trend (make-array n :initial-element 0.0d0))
           (seas (make-array n :initial-element 0.0d0))
           (fit (make-array n :initial-element 0.0d0))
           (l0 (/ (loop for i from 0 below m sum (aref ys i)) m))
           (l1 (/ (loop for i from m below (* 2 m) sum (aref ys i)) m))
           (t0 (/ (- l1 l0) m))
           (s0 (make-array m :initial-element 0.0d0)))
      (loop for i from 0 below m
            do (setf (aref s0 i) (- (aref ys i) l0)))
      (setf (aref level 0) l0
            (aref trend 0) t0
            (aref seas 0) (aref s0 0)
            (aref fit 0) (+ l0 (aref s0 0)))
      (loop for t_ from 1 below n
            for sidx = (mod t_ m)
            for prev-s = (if (< t_ m) (aref s0 sidx) (aref seas (- t_ m)))
            for y = (aref ys t_)
            for l = (+ (* alpha (- y prev-s))
                       (* (- 1.0d0 alpha) (+ (aref level (1- t_))
                                             (aref trend (1- t_)))))
            for b = (+ (* beta (- l (aref level (1- t_))))
                       (* (- 1.0d0 beta) (aref trend (1- t_))))
            for s = (+ (* gamma (- y l)) (* (- 1.0d0 gamma) prev-s))
            do (setf (aref level t_) l
                     (aref trend t_) b
                     (aref seas t_) s
                     (aref fit t_) (+ (aref level (1- t_))
                                      (aref trend (1- t_))
                                      prev-s)))
      (let* ((resid (loop for i from m below n
                          collect (- (aref ys i) (aref fit i))))
             (sigma (if resid
                        (sqrt (/ (reduce #'+ resid :key (lambda (e) (* e e)))
                                 (length resid)))
                        1.0d0)))
        (values level trend seas fit sigma))))

  (defun viterbi-2 (obs mu0 mu1 var pstay)
    (let* ((n (length obs))
           (log-stay (log pstay))
           (log-sw (log (- 1.0d0 pstay)))
           (dp0 (make-array n :initial-element 0.0d0))
           (dp1 (make-array n :initial-element 0.0d0))
           (bt0 (make-array n :initial-element 0))
           (bt1 (make-array n :initial-element 1))
           (norm (* -0.5d0 (log (* 2.0d0 pi var)))))
      (flet ((emit (x mu)
               (+ norm (/ (- (* (- x mu) (- x mu))) (* 2.0d0 var)))))
        (setf (aref dp0 0) (emit (aref obs 0) mu0)
              (aref dp1 0) (emit (aref obs 0) mu1))
        (loop for t_ from 1 below n
              for e0 = (emit (aref obs t_) mu0)
              for e1 = (emit (aref obs t_) mu1)
              for s00 = (+ (aref dp0 (1- t_)) log-stay)
              for s10 = (+ (aref dp1 (1- t_)) log-sw)
              for s01 = (+ (aref dp0 (1- t_)) log-sw)
              for s11 = (+ (aref dp1 (1- t_)) log-stay)
              do (if (>= s00 s10)
                     (setf (aref dp0 t_) (+ e0 s00) (aref bt0 t_) 0)
                     (setf (aref dp0 t_) (+ e0 s10) (aref bt0 t_) 1))
                 (if (>= s11 s01)
                     (setf (aref dp1 t_) (+ e1 s11) (aref bt1 t_) 1)
                     (setf (aref dp1 t_) (+ e1 s01) (aref bt1 t_) 0)))
        (let* ((last (if (>= (aref dp1 (1- n)) (aref dp0 (1- n))) 1 0))
               (path (make-array n :initial-element 0))
               (lp (make-array n :initial-element 0.0d0)))
          (setf (aref path (1- n)) last
                (aref lp (1- n)) (if (= last 0)
                                     (aref dp0 (1- n))
                                     (aref dp1 (1- n))))
          (loop for t_ from (- n 2) downto 0
                for st = (aref path (1+ t_))
                for prev = (if (zerop st) (aref bt0 (1+ t_)) (aref bt1 (1+ t_)))
                do (setf (aref path t_) prev
                         (aref lp t_) (if (zerop prev)
                                          (aref dp0 t_)
                                          (aref dp1 t_))))
          (values path lp))))))
$plecl$;

-- Weighted interval scheduling: max-revenue non-overlapping [ship, receipt] windows.
-- DP + predecessor binary search. SQL cannot express the opt + backpointers cleanly.
CREATE FUNCTION tpch_interval_schedule(supplier_id integer, start_day integer, end_day integer)
RETURNS SETOF tpch_interval_pick
LANGUAGE plecl AS $plecl$
(let* ((sid (if (plecl:sql-null-p supplier_id) 1 supplier_id))
       (lo (if (plecl:sql-null-p start_day) 0 start_day))
       (hi (if (plecl:sql-null-p end_day) 100000 end_day))
       (rows (plecl:query
              "SELECT l_linenumber AS linenumber,
                      l_orderkey AS orderkey,
                      (l_shipdate - DATE '1992-01-01')::int AS start_day,
                      GREATEST((l_receiptdate - DATE '1992-01-01')::int,
                               (l_shipdate - DATE '1992-01-01')::int + 1) AS end_day,
                      (l_extendedprice * (1 - l_discount))::float8 AS revenue
                 FROM lineitem
                WHERE l_suppkey = $1
                  AND (l_shipdate - DATE '1992-01-01') >= $2
                  AND (l_shipdate - DATE '1992-01-01') <= $3"
              sid lo hi))
       (items (coerce
               (loop for r in rows
                     collect (list (tpch-int (tpch-get r :linenumber))
                                   (tpch-int (tpch-get r :orderkey))
                                   (tpch-int (tpch-get r :start_day))
                                   (tpch-int (tpch-get r :end_day))
                                   (tpch-num (tpch-get r :revenue))))
               'vector)))
  (multiple-value-bind (v chosen) (weighted-interval items)
    (loop for i from 0 below (length v)
          for it = (aref v i)
          collect (tpch-alist :linenumber (first it)
                              :orderkey (second it)
                              :start_day (third it)
                              :end_day (fourth it)
                              :revenue (fifth it)
                              :taken (aref chosen i)))))
$plecl$;

-- Binary segmentation on daily net revenue (prefix RSS, recursive splits).
CREATE FUNCTION tpch_changepoints(supplier_id integer, min_size integer, penalty double precision)
RETURNS SETOF tpch_segment
LANGUAGE plecl AS $plecl$
(let* ((sid (if (plecl:sql-null-p supplier_id) 1 supplier_id))
       (ms (max 2 (if (plecl:sql-null-p min_size) 8 min_size)))
       (pen (if (plecl:sql-null-p penalty) 50.0d0 (tpch-num penalty)))
       (rows (plecl:query
              "SELECT (l_shipdate - DATE '1992-01-01')::int AS day,
                      SUM(l_extendedprice * (1 - l_discount))::float8 AS rev
                 FROM lineitem
                WHERE l_suppkey = $1
                GROUP BY 1
                ORDER BY 1"
              sid))
       (n (length rows))
       (xs (make-array n :initial-element 0.0d0))
       (days (make-array n :initial-element 0)))
  (loop for r in rows for i from 0
        do (setf (aref days i) (tpch-int (tpch-get r :day))
                 (aref xs i) (tpch-num (tpch-get r :rev))))
  (loop for s in (binary-segment xs days ms pen)
        for i from 1
        collect (tpch-alist :seg i
                            :start_day (first s)
                            :end_day (second s)
                            :n (third s)
                            :mean_rev (fourth s)
                            :rss (fifth s))))
$plecl$;

-- k-means++ on standardized supplier features (SQL GROUP BY, Lisp iterates).
CREATE FUNCTION tpch_supplier_kmeans(k integer, n_iter integer)
RETURNS SETOF tpch_cluster
LANGUAGE plecl AS $plecl$
(let* ((kk (max 1 (if (plecl:sql-null-p k) 3 k)))
       (iters (max 1 (if (plecl:sql-null-p n_iter) 12 n_iter)))
       (rows (plecl:query
              "SELECT l_suppkey AS supplier,
                      AVG(l_discount)::float8 AS discount,
                      AVG((l_receiptdate - l_commitdate)::float8) AS delay,
                      AVG((l_returnflag = 'R')::int)::float8 AS return_rate,
                      LN(GREATEST(SUM(l_extendedprice * (1 - l_discount)), 1))::float8 AS log_rev
                 FROM lineitem
                GROUP BY 1"))
       (n (length rows))
       (raw (make-array n))
       (nfeat 4))
  (loop for r in rows for i from 0
        do (setf (aref raw i)
                 (vector (tpch-int (tpch-get r :supplier))
                         (tpch-num (tpch-get r :discount))
                         (tpch-num (tpch-get r :delay))
                         (tpch-num (tpch-get r :return_rate))
                         (tpch-num (tpch-get r :log_rev)))))
  (let ((pts (make-array n)))
    (loop for i from 0 below n
          do (setf (aref pts i) (copy-seq (aref raw i))))
    (standardize-cols pts nfeat)
    (multiple-value-bind (assign cent) (kmeans pts kk iters nfeat)
      (declare (ignore cent))
      (loop for i from 0 below n
            for r = (aref raw i)
            collect (tpch-alist :supplier (aref r 0)
                                :cluster (aref assign i)
                                :discount (aref r 1)
                                :delay (aref r 2)
                                :return_rate (aref r 3)
                                :log_rev (aref r 4))))))
$plecl$;

-- Additive Holt-Winters on weekly revenue; forecast + residual interval.
CREATE FUNCTION tpch_holt_winters(supplier_id integer, season integer, horizon integer)
RETURNS SETOF tpch_forecast
LANGUAGE plecl AS $plecl$
(let* ((sid (if (plecl:sql-null-p supplier_id) 1 supplier_id))
       (m (max 2 (if (plecl:sql-null-p season) 4 season)))
       (h (max 1 (if (plecl:sql-null-p horizon) 4 horizon)))
       (rows (plecl:query
              "SELECT (EXTRACT(YEAR FROM l_shipdate)::int * 100
                       + EXTRACT(WEEK FROM l_shipdate)::int) AS week,
                      SUM(l_extendedprice * (1 - l_discount))::float8 AS rev
                 FROM lineitem
                WHERE l_suppkey = $1
                GROUP BY 1
                ORDER BY 1"
              sid))
       (n (length rows)))
  (when (< n (* 2 m))
    (error "holt-winters needs >= ~d weekly points, got ~d" (* 2 m) n))
  (let* ((weeks (map 'vector (lambda (r) (tpch-int (tpch-get r :week))) rows))
         (ys (map 'vector (lambda (r) (tpch-num (tpch-get r :rev))) rows)))
    (multiple-value-bind (level trend seas fit sigma)
        (holt-winters ys m 0.3d0 0.1d0 0.3d0)
      (append
       (loop for i from 0 below n
             collect (tpch-alist :week (aref weeks i)
                                 :actual (aref ys i)
                                 :fitted (aref fit i)
                                 :yhat (aref fit i)
                                 :lo (- (aref fit i) (* 1.96d0 sigma))
                                 :hi (+ (aref fit i) (* 1.96d0 sigma))))
       (let ((lt (aref level (1- n)))
             (bt (aref trend (1- n))))
         (loop for step from 1 to h
               for s = (aref seas (+ (- n m) (mod (1- step) m)))
               for yhat = (+ lt (* step bt) s)
               collect (tpch-alist :week (+ (aref weeks (1- n)) step)
                                   :actual plecl:+null+
                                   :fitted plecl:+null+
                                   :yhat yhat
                                   :lo (- yhat (* 1.96d0 sigma))
                                   :hi (+ yhat (* 1.96d0 sigma)))))))))
$plecl$;

-- 2-state Gaussian HMM + Viterbi on daily late-receipt fraction.
CREATE FUNCTION tpch_late_viterbi(supplier_id integer)
RETURNS SETOF tpch_regime
LANGUAGE plecl AS $plecl$
(let* ((sid (if (plecl:sql-null-p supplier_id) 1 supplier_id))
       (rows (plecl:query
              "SELECT (l_shipdate - DATE '1992-01-01')::int AS day,
                      AVG(CASE WHEN l_receiptdate > l_commitdate THEN 1.0 ELSE 0.0 END)::float8
                        AS late_frac
                 FROM lineitem
                WHERE l_suppkey = $1
                GROUP BY 1
                ORDER BY 1"
              sid))
       (n (length rows)))
  (if (< n 2)
      '()
  (let* ((days (map 'vector (lambda (r) (tpch-int (tpch-get r :day))) rows))
         (xs (map 'vector (lambda (r) (tpch-num (tpch-get r :late_frac))) rows))
         (sorted (sort (copy-seq xs) #'<))
         (mu0 (aref sorted (floor (* n 0.25d0))))
         (mu1 (aref sorted (min (1- n) (floor (* n 0.75d0)))))
         (mu0 (if (= mu0 mu1) 0.15d0 mu0))
         (mu1 (if (= mu0 mu1) 0.75d0 mu1))
         (var (max 1d-4
                   (/ (loop for x across xs
                            for m = (/ (+ mu0 mu1) 2)
                            sum (* (- x m) (- x m)))
                      n))))
    (multiple-value-bind (path lp) (viterbi-2 xs mu0 mu1 var 0.88d0)
      (loop for i from 0 below n
            collect (tpch-alist :day (aref days i)
                                :late_frac (aref xs i)
                                :state (if (zerop (aref path i)) "ok" "late")
                                :logp (aref lp i)))))))
$plecl$;
