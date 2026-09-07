-- TPC-H lineitem (SF1 ≈ 6,001,215 rows / ~725MB). Enough for every UDF here.
CREATE TABLE IF NOT EXISTS lineitem (
  l_orderkey       bigint NOT NULL,
  l_partkey        integer NOT NULL,
  l_suppkey        integer NOT NULL,
  l_linenumber     integer NOT NULL,
  l_quantity       double precision NOT NULL,
  l_extendedprice  double precision NOT NULL,
  l_discount       double precision NOT NULL,
  l_tax            double precision NOT NULL,
  l_returnflag     char(1) NOT NULL,
  l_linestatus     char(1) NOT NULL,
  l_shipdate       date NOT NULL,
  l_commitdate     date NOT NULL,
  l_receiptdate    date NOT NULL,
  l_shipinstruct   varchar(25) NOT NULL,
  l_shipmode       varchar(10) NOT NULL,
  l_comment        varchar(44) NOT NULL
);
