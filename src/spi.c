#include "plecl.h"

static void
object_to_spi_arg(cl_object obj, Oid *typid, Datum *value, char *nulls)
{
	if (plecl_sql_null_p(obj))
	{
		*typid = TEXTOID;
		*value = (Datum) 0;
		*nulls = 'n';
		return;
	}
	*nulls = ' ';
	if (obj == ECL_T)
	{
		*typid = BOOLOID;
		*value = BoolGetDatum(true);
		return;
	}
	if (obj == ECL_NIL)
	{
		*typid = BOOLOID;
		*value = BoolGetDatum(false);
		return;
	}
	if (ECL_FIXNUMP(obj) || ECL_BIGNUMP(obj))
	{
		*typid = INT8OID;
		*value = Int64GetDatum(ecl_to_int64_t(obj));
		return;
	}
	if (ECL_SINGLE_FLOAT_P(obj) || ECL_DOUBLE_FLOAT_P(obj) || ECL_LONG_FLOAT_P(obj)
		|| (!ECL_IMMEDIATE(obj) && obj->d.t == t_ratio))
	{
		*typid = FLOAT8OID;
		*value = Float8GetDatum(ecl_to_double(obj));
		return;
	}
	if (ECL_VECTORP(obj) && ecl_array_elttype(obj) == ecl_aet_b8)
	{
		int			n = obj->vector.fillp;
		bytea	   *b = (bytea *) palloc(VARHDRSZ + n);

		SET_VARSIZE(b, VARHDRSZ + n);
		memcpy(VARDATA(b), obj->vector.self.b8, n);
		*typid = BYTEAOID;
		*value = PointerGetDatum(b);
		return;
	}
	{
		char	   *s = plecl_cstring_palloc(obj);

		*typid = TEXTOID;
		*value = CStringGetTextDatum(s ? s : "");
	}
}

static cl_object
spi_tuptable_to_list(SPITupleTable *tuptable)
{
	cl_object	rows = ECL_NIL;
	uint64		i;

	if (tuptable == NULL)
		return ECL_NIL;
	for (i = 0; i < tuptable->numvals; i++)
		rows = cl_cons(plecl_tuple_to_object(tuptable->vals[i], tuptable->tupdesc), rows);
	return cl_nreverse(rows);
}

static cl_object
spi_run(cl_object sql_obj, cl_object args_obj, bool want_rows)
{
	char	   *sql;
	int			nargs = 0;
	Oid		   *types = NULL;
	Datum	   *values = NULL;
	char	   *nulls = NULL;
	int			ret;
	cl_object	result;
	cl_object	c;
	int			i;
	MemoryContext oldcontext = CurrentMemoryContext;

	sql = plecl_cstring_palloc(sql_obj);
	if (sql == NULL || sql[0] == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("plecl: empty SQL")));

	if (ECL_LISTP(args_obj) && args_obj != ECL_NIL)
		nargs = fixint(cl_length(args_obj));
	else if (args_obj != ECL_NIL && args_obj != ECL_T)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("plecl: SPI args must be a list")));

	if (nargs > 0)
	{
		types = (Oid *) palloc(sizeof(Oid) * nargs);
		values = (Datum *) palloc(sizeof(Datum) * nargs);
		nulls = (char *) palloc(sizeof(char) * nargs);
		for (i = 0, c = args_obj; i < nargs; i++, c = ECL_CONS_CDR(c))
			object_to_spi_arg(ECL_CONS_CAR(c), &types[i], &values[i], &nulls[i]);
	}

	if (SPI_connect() != SPI_OK_CONNECT)
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: SPI_connect failed")));

	PG_TRY();
	{
		ret = SPI_execute_with_args(sql, nargs, types, values, nulls, false, 0);
		if (ret < 0)
			ereport(ERROR,
					(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
					 errmsg("plecl: SPI_execute failed (%d)", ret)));
		MemoryContextSwitchTo(oldcontext);
		if (want_rows && SPI_tuptable != NULL)
			result = spi_tuptable_to_list(SPI_tuptable);
		else
			result = ecl_make_uint64_t((uint64) SPI_processed);
	}
	PG_CATCH();
	{
		SPI_finish();
		PG_RE_THROW();
	}
	PG_END_TRY();

	SPI_finish();
	return result;
}

cl_object
plecl_c_spi_execute(cl_object sql, cl_object args)
{
	return spi_run(sql, args, false);
}

cl_object
plecl_c_spi_execute_rows(cl_object sql, cl_object args)
{
	return spi_run(sql, args, true);
}

void
plecl_register_spi(void)
{
	ecl_def_c_function(ecl_make_symbol("%SPI-EXECUTE", PLECL_PACKAGE),
					   (cl_objectfn_fixed) plecl_c_spi_execute, 2);
	ecl_def_c_function(ecl_make_symbol("%SPI-QUERY", PLECL_PACKAGE),
					   (cl_objectfn_fixed) plecl_c_spi_execute_rows, 2);
}
