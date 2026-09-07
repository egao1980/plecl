# TPC-H analytics in plecl

SQL does the scan/`GROUP BY`. Lisp runs algorithms plpgsql cannot express without pain:

| function | algorithm | why not SQL |
|---|---|---|
| `tpch_interval_schedule` | weighted interval scheduling (DP + pred binary search) | opt + backpointers |
| `tpch_changepoints` | binary segmentation on prefix RSS | recursive splits |
| `tpch_supplier_kmeans` | k-means++ on 4-D standardized features | iterative assignment |
| `tpch_holt_winters` | additive Holt–Winters + residual interval | seasonal state |
| `tpch_late_viterbi` | 2-state Gaussian HMM, Viterbi path | DP on regimes |

`lineitem` only. SF1 ≈ 6,001,215 rows / ~725MB raw; `TPCH_ROWS=6000000` synth is the same cardinality (supplier 1 is 5% so partitions are fat).

```bash
createdb plecl_tpch
TPCH_ROWS=200000 ./examples/tpch/load.sh
psql -d plecl_tpch -f examples/tpch/profile.sql

# real TPC-H
TPCH_SCALE=1 ./examples/tpch/load.sh   # needs duckdb

# docker
docker run --rm -e TPCH_ROWS=6000000 --entrypoint bash plecl-test /src/docker/run-profile.sh
```

Do **not** `plecl:query` the whole fact table into a cons list. These UDFs pull one supplier or a `GROUP BY` feature matrix.
