#ifndef PLECL_H
#define PLECL_H

#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"
#include "access/htup_details.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "commands/trigger.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/syscache.h"
#include "utils/typcache.h"
#include "mb/pg_wchar.h"

#ifdef ERROR
#define PLECL_PG_ERROR ERROR
#undef ERROR
#endif
#include <ecl/ecl.h>
#ifdef ERROR
#undef ERROR
#endif
#ifdef PLECL_PG_ERROR
#define ERROR PLECL_PG_ERROR
#undef PLECL_PG_ERROR
#endif

#define PLECL_PACKAGE "PLECL"

cl_object plecl_symbol(const char *name);
cl_object plecl_keyword(const char *name);
cl_object plecl_null_object(void);
cl_object plecl_apply(const char *name, cl_object args);
cl_object plecl_funcall1(const char *name, cl_object a);
cl_object plecl_funcall2(const char *name, cl_object a, cl_object b);

cl_object plecl_string(const char *s, Size len);
char *plecl_cstring_palloc(cl_object obj);
bool plecl_sql_null_p(cl_object obj);

cl_object plecl_datum_to_object(Oid typid, Datum d, bool isnull);
Datum plecl_object_to_datum(Oid typid, int32 typmod, cl_object obj, bool *isnull);
cl_object plecl_tuple_to_object(HeapTuple tuple, TupleDesc tupdesc);
HeapTuple plecl_object_to_tuple(cl_object obj, TupleDesc tupdesc);

void plecl_register_runtime(void);
void plecl_register_spi(void);
cl_object plecl_c_ereport(cl_object message);
cl_object plecl_c_debugger(cl_object condition, cl_object hook);
cl_object plecl_c_spi_execute(cl_object sql, cl_object args);
cl_object plecl_c_spi_execute_rows(cl_object sql, cl_object args);

#endif
