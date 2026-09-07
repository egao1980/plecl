#include "plecl.h"

#include "funcapi.h"
#include "nodes/parsenodes.h"
#include "utils/rel.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(plecl_call_handler);
PG_FUNCTION_INFO_V1(plecl_inline_handler);
PG_FUNCTION_INFO_V1(plecl_validator);

static bool		ecl_booted = false;

cl_object
plecl_symbol(const char *name)
{
	return ecl_make_symbol(name, PLECL_PACKAGE);
}

cl_object
plecl_keyword(const char *name)
{
	return ecl_make_keyword(name);
}

cl_object
plecl_null_object(void)
{
	return cl_symbol_value(plecl_symbol("+NULL+"));
}

bool
plecl_sql_null_p(cl_object obj)
{
	return obj == plecl_null_object();
}

/* Lisp debugger hook → ereport(ERROR). Never returns. */
cl_object
plecl_c_ereport(cl_object message)
{
	char	   *s;

	s = plecl_cstring_palloc(message);
	ereport(ERROR,
			(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
			 errmsg("%s", (s && s[0]) ? s : "plecl error")));
	return ECL_NIL;
}

void
plecl_register_runtime(void)
{
	ecl_def_c_function(ecl_make_symbol("%EREPORT", PLECL_PACKAGE),
					   (cl_objectfn_fixed) plecl_c_ereport, 1);
}

cl_object
plecl_apply(const char *name, cl_object args)
{
	cl_object	fun = cl_fdefinition(plecl_symbol(name));
	cl_env_ptr	env = ecl_process_env();
	cl_object	result = ECL_NIL;

	ECL_CATCH_ALL_BEGIN(env)
	{
		result = cl_apply(2, fun, args);
	}
	ECL_CATCH_ALL_IF_CAUGHT
	{
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: uncaught non-local exit in %s", name)));
	}
	ECL_CATCH_ALL_END;
	return result;
}

cl_object
plecl_funcall1(const char *name, cl_object a)
{
	return plecl_apply(name, cl_cons(a, ECL_NIL));
}

cl_object
plecl_funcall2(const char *name, cl_object a, cl_object b)
{
	return plecl_apply(name, cl_cons(a, cl_cons(b, ECL_NIL)));
}

static void
boot_ecl(void)
{
	char	   *argv[2];
	char		lisp_path[MAXPGPATH];
	cl_object	path;
	cl_env_ptr	env;

	if (ecl_booted)
		return;

	argv[0] = "plecl";
	argv[1] = NULL;
	ecl_set_option(ECL_OPT_TRAP_SIGFPE, 0);
	ecl_set_option(ECL_OPT_TRAP_SIGSEGV, 0);
	ecl_set_option(ECL_OPT_TRAP_SIGINT, 0);
	ecl_set_option(ECL_OPT_TRAP_SIGILL, 0);
	ecl_set_option(ECL_OPT_TRAP_SIGBUS, 0);
	ecl_set_option(ECL_OPT_TRAP_SIGPIPE, 0);
	ecl_set_option(ECL_OPT_TRAP_INTERRUPT_SIGNAL, 0);
	if (cl_boot(1, argv) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: cl_boot failed")));

	env = ecl_process_env();
	ECL_CATCH_ALL_BEGIN(env)
	{
		plecl_register_runtime();
		snprintf(lisp_path, sizeof(lisp_path), "%s/plecl.lisp", pkglib_path);
		path = plecl_string(lisp_path, strlen(lisp_path));
		cl_load(1, path);
		plecl_register_spi();
		(void) plecl_apply("BOOT", ECL_NIL);
	}
	ECL_CATCH_ALL_IF_CAUGHT
	{
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: failed to load %s", lisp_path)));
	}
	ECL_CATCH_ALL_END;
	ecl_booted = true;
}

void
_PG_init(void)
{
	boot_ecl();
}

void
_PG_fini(void)
{
	if (ecl_booted)
	{
		cl_shutdown();
		ecl_booted = false;
	}
}

static char *
text_to_cstring_copy(Datum d)
{
	return TextDatumGetCString(d);
}

static cl_object
proc_arg_names(HeapTuple protup, int nargs)
{
	Datum		names_d;
	bool		isnull;
	cl_object	list = ECL_NIL;
	int			i;

	names_d = SysCacheGetAttr(PROCOID, protup, Anum_pg_proc_proargnames, &isnull);
	if (!isnull)
	{
		ArrayType  *arr = DatumGetArrayTypeP(names_d);
		Datum	   *elems;
		int			nelems;

		deconstruct_array(arr, TEXTOID, -1, false, TYPALIGN_INT,
						  &elems, NULL, &nelems);
		for (i = nelems - 1; i >= 0; i--)
		{
			char	   *n = TextDatumGetCString(elems[i]);
			char		up[NAMEDATALEN];
			int			j;

			if (n[0] == '\0')
				snprintf(up, sizeof(up), "ARG%d", i);
			else
			{
				for (j = 0; n[j] && j < NAMEDATALEN - 1; j++)
					up[j] = pg_ascii_toupper((unsigned char) n[j]);
				up[j] = '\0';
			}
			list = cl_cons(ecl_make_symbol(up, "PLECL.USER"), list);
		}
		return list;
	}

	for (i = nargs - 1; i >= 0; i--)
	{
		char		up[32];

		snprintf(up, sizeof(up), "ARG%d", i);
		list = cl_cons(ecl_make_symbol(up, "PLECL.USER"), list);
	}
	return list;
}

static cl_object
arg_values_list(FunctionCallInfo fcinfo, Form_pg_proc proc)
{
	cl_object	list = ECL_NIL;
	int			i;

	for (i = proc->pronargs - 1; i >= 0; i--)
	{
		Oid			typid = proc->proargtypes.values[i];
		bool		isnull = PG_ARGISNULL(i);
		Datum		d = isnull ? (Datum) 0 : PG_GETARG_DATUM(i);

		list = cl_cons(plecl_datum_to_object(typid, d, isnull), list);
	}
	return list;
}

static cl_object
keyword_eq(cl_object obj, const char *name)
{
	return (obj == ecl_make_keyword(name)) ? ECL_T : ECL_NIL;
}

static cl_object
unwrap_status(cl_object boxed, cl_object *payload)
{
	cl_object	tag;

	if (!ECL_CONSP(boxed))
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: dispatch returned a non-cons")));
	tag = ECL_CONS_CAR(boxed);
	*payload = ECL_CONS_CDR(boxed);
	if (keyword_eq(tag, "ERROR") == ECL_T)
	{
		char	   *msg = plecl_cstring_palloc(*payload);

		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: %s", msg ? msg : "error")));
	}
	return tag;
}

static cl_object
trigger_plist(FunctionCallInfo fcinfo)
{
	TriggerData *td = (TriggerData *) fcinfo->context;
	Trigger    *trig = td->tg_trigger;
	Relation	rel = td->tg_relation;
	TupleDesc	tupdesc = RelationGetDescr(rel);
	cl_object	plist = ECL_NIL;
	const char *op;
	const char *level;
	const char *when;
	int			i;

	if (TRIGGER_FIRED_BY_INSERT(td->tg_event))
		op = "INSERT";
	else if (TRIGGER_FIRED_BY_DELETE(td->tg_event))
		op = "DELETE";
	else if (TRIGGER_FIRED_BY_UPDATE(td->tg_event))
		op = "UPDATE";
	else if (TRIGGER_FIRED_BY_TRUNCATE(td->tg_event))
		op = "TRUNCATE";
	else
		op = "UNKNOWN";

	level = TRIGGER_FIRED_FOR_ROW(td->tg_event) ? "ROW" : "STATEMENT";
	when = TRIGGER_FIRED_BEFORE(td->tg_event) ? "BEFORE" :
		(TRIGGER_FIRED_AFTER(td->tg_event) ? "AFTER" : "INSTEAD");

	plist = cl_cons(ecl_make_keyword("TG-NAME"),
					cl_cons(plecl_string(trig->tgname, strlen(trig->tgname)), plist));
	plist = cl_cons(ecl_make_keyword("TG-OP"),
					cl_cons(ecl_make_keyword(op), plist));
	plist = cl_cons(ecl_make_keyword("TG-LEVEL"),
					cl_cons(ecl_make_keyword(level), plist));
	plist = cl_cons(ecl_make_keyword("TG-WHEN"),
					cl_cons(ecl_make_keyword(when), plist));
	plist = cl_cons(ecl_make_keyword("TG-TABLE"),
					cl_cons(plecl_string(RelationGetRelationName(rel),
										 strlen(RelationGetRelationName(rel))),
							plist));

	if (td->tg_trigtuple)
		plist = cl_cons(ecl_make_keyword("OLD"),
						cl_cons(plecl_tuple_to_object(td->tg_trigtuple, tupdesc), plist));
	else
		plist = cl_cons(ecl_make_keyword("OLD"),
						cl_cons(plecl_null_object(), plist));

	if (td->tg_newtuple)
		plist = cl_cons(ecl_make_keyword("NEW"),
						cl_cons(plecl_tuple_to_object(td->tg_newtuple, tupdesc), plist));
	else if (TRIGGER_FIRED_BY_INSERT(td->tg_event) && td->tg_trigtuple)
		plist = cl_cons(ecl_make_keyword("NEW"),
						cl_cons(plecl_tuple_to_object(td->tg_trigtuple, tupdesc), plist));
	else
		plist = cl_cons(ecl_make_keyword("NEW"),
						cl_cons(plecl_null_object(), plist));

	{
		cl_object	args = ECL_NIL;

		for (i = trig->tgnargs - 1; i >= 0; i--)
			args = cl_cons(plecl_string(trig->tgargs[i], strlen(trig->tgargs[i])), args);
		plist = cl_cons(ecl_make_keyword("TG-ARGS"), cl_cons(args, plist));
	}
	return plist;
}

static Datum
handle_trigger(FunctionCallInfo fcinfo, HeapTuple protup, Form_pg_proc proc,
			   char *src, TransactionId xmin)
{
	TriggerData *td = (TriggerData *) fcinfo->context;
	TupleDesc	tupdesc = RelationGetDescr(td->tg_relation);
	cl_object	boxed;
	cl_object	tag;
	cl_object	payload;
	cl_object	args;

	args = cl_list(6,
				   ecl_make_uint32_t(fcinfo->flinfo->fn_oid),
				   ecl_make_uint32_t(xmin),
				   plecl_string(src, strlen(src)),
				   ECL_NIL,
				   ECL_NIL,
				   trigger_plist(fcinfo));
	boxed = plecl_apply("DISPATCH-TRIGGER", args);
	tag = unwrap_status(boxed, &payload);

	if (keyword_eq(tag, "SKIP") == ECL_T)
		return PointerGetDatum(NULL);
	if (keyword_eq(tag, "OK") == ECL_T)
	{
		if (TRIGGER_FIRED_BY_DELETE(td->tg_event))
			return PointerGetDatum(td->tg_trigtuple);
		if (td->tg_newtuple)
			return PointerGetDatum(td->tg_newtuple);
		return PointerGetDatum(td->tg_trigtuple);
	}
	if (keyword_eq(tag, "ROW") == ECL_T)
		return PointerGetDatum(plecl_object_to_tuple(payload, tupdesc));

	ereport(ERROR,
			(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
			 errmsg("plecl: trigger must return :ok, :skip, or an alist")));
	return (Datum) 0;
}

static Datum
srf_next_datum(FunctionCallInfo fcinfo, Form_pg_proc proc,
			   cl_object payload, bool *isnull)
{
	ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;

	if (rsinfo && rsinfo->expectedDesc && type_is_rowtype(proc->prorettype))
	{
		HeapTuple	tup = plecl_object_to_tuple(payload, rsinfo->expectedDesc);

		*isnull = false;
		return HeapTupleGetDatum(tup);
	}
	return plecl_object_to_datum(proc->prorettype, -1, payload, isnull);
}

static Datum
handle_srf(FunctionCallInfo fcinfo, Form_pg_proc proc, char *src,
		   TransactionId xmin, cl_object argnames, cl_object argvals)
{
	FuncCallContext *funcctx;
	uint32		key;
	cl_object	boxed;
	cl_object	tag;
	cl_object	payload;
	bool		isnull;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext old;
		cl_object	keyobj;
		cl_object	lenobj;

		funcctx = SRF_FIRSTCALL_INIT();
		old = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		boxed = plecl_apply("DISPATCH-SET",
							cl_list(5,
									ecl_make_uint32_t(fcinfo->flinfo->fn_oid),
									ecl_make_uint32_t(xmin),
									plecl_string(src, strlen(src)),
									argnames,
									argvals));
		tag = unwrap_status(boxed, &payload);
		if (keyword_eq(tag, "SET") != ECL_T || !ECL_CONSP(payload))
			ereport(ERROR,
					(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
					 errmsg("plecl: set-returning function must return a list")));
		keyobj = ECL_CONS_CAR(payload);
		lenobj = ECL_CONS_CDR(payload);
		funcctx->max_calls = (lenobj == ECL_NIL) ? 0 : fixint(lenobj);
		funcctx->user_fctx = (void *) (intptr_t) ecl_to_uint32_t(keyobj);
		MemoryContextSwitchTo(old);
	}

	funcctx = SRF_PERCALL_SETUP();
	key = (uint32) (intptr_t) funcctx->user_fctx;
	if (funcctx->call_cntr >= funcctx->max_calls)
	{
		(void) plecl_funcall1("SRF-DONE", ecl_make_uint32_t(key));
		SRF_RETURN_DONE(funcctx);
	}

	boxed = plecl_funcall2("SRF-NTH",
						   ecl_make_uint32_t(key),
						   ecl_make_uint32_t((uint32) funcctx->call_cntr));
	tag = unwrap_status(boxed, &payload);
	if (keyword_eq(tag, "NULL") == ECL_T)
	{
		fcinfo->isnull = true;
		SRF_RETURN_NEXT(funcctx, (Datum) 0);
	}
	{
		Datum		d = srf_next_datum(fcinfo, proc, payload, &isnull);

		if (isnull)
		{
			fcinfo->isnull = true;
			SRF_RETURN_NEXT(funcctx, (Datum) 0);
		}
		SRF_RETURN_NEXT(funcctx, d);
	}
}

static Datum
handle_ordinary(FunctionCallInfo fcinfo, Form_pg_proc proc, char *src,
				TransactionId xmin, cl_object argnames, cl_object argvals)
{
	cl_object	boxed;
	cl_object	tag;
	cl_object	payload;
	bool		isnull;
	Datum		d;

	boxed = plecl_apply("DISPATCH",
						cl_list(5,
								ecl_make_uint32_t(fcinfo->flinfo->fn_oid),
								ecl_make_uint32_t(xmin),
								plecl_string(src, strlen(src)),
								argnames,
								argvals));
	tag = unwrap_status(boxed, &payload);
	if (keyword_eq(tag, "NULL") == ECL_T)
	{
		fcinfo->isnull = true;
		return (Datum) 0;
	}
	if (keyword_eq(tag, "OK") != ECL_T)
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("plecl: unexpected dispatch tag")));
	d = plecl_object_to_datum(proc->prorettype, -1, payload, &isnull);
	fcinfo->isnull = isnull;
	return d;
}

Datum
plecl_call_handler(PG_FUNCTION_ARGS)
{
	HeapTuple	protup;
	Form_pg_proc proc;
	char	   *src;
	bool		isnull;
	TransactionId xmin;
	cl_object	argnames;
	cl_object	argvals;

	boot_ecl();

	protup = SearchSysCache1(PROCOID, ObjectIdGetDatum(fcinfo->flinfo->fn_oid));
	if (!HeapTupleIsValid(protup))
		elog(ERROR, "plecl: cache lookup failed for function %u", fcinfo->flinfo->fn_oid);
	proc = (Form_pg_proc) GETSTRUCT(protup);
	src = text_to_cstring_copy(SysCacheGetAttr(PROCOID, protup, Anum_pg_proc_prosrc, &isnull));
	if (isnull)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("plecl: function has no source")));
	xmin = HeapTupleHeaderGetRawXmin(protup->t_data);

	if (CALLED_AS_TRIGGER(fcinfo))
	{
		Datum		r = handle_trigger(fcinfo, protup, proc, src, xmin);

		ReleaseSysCache(protup);
		return r;
	}

	argnames = proc_arg_names(protup, proc->pronargs);
	argvals = arg_values_list(fcinfo, proc);

	if (proc->proretset)
	{
		Datum		r = handle_srf(fcinfo, proc, src, xmin, argnames, argvals);

		ReleaseSysCache(protup);
		return r;
	}

	{
		Datum		r = handle_ordinary(fcinfo, proc, src, xmin, argnames, argvals);

		ReleaseSysCache(protup);
		return r;
	}
}

Datum
plecl_inline_handler(PG_FUNCTION_ARGS)
{
	InlineCodeBlock *codeblock = (InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0));
	cl_object	boxed;
	cl_object	payload;
	cl_object	tag;

	boot_ecl();
	boxed = plecl_funcall1("EVAL-SOURCE",
						   plecl_string(codeblock->source_text,
										strlen(codeblock->source_text)));
	tag = unwrap_status(boxed, &payload);
	(void) tag;
	PG_RETURN_VOID();
}

Datum
plecl_validator(PG_FUNCTION_ARGS)
{
	Oid			funcoid = PG_GETARG_OID(0);
	HeapTuple	protup;
	Form_pg_proc proc;
	char	   *src;
	bool		isnull;
	cl_object	boxed;
	cl_object	payload;

	if (!CheckFunctionValidatorAccess(fcinfo->flinfo->fn_oid, funcoid))
		PG_RETURN_VOID();

	boot_ecl();
	protup = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcoid));
	if (!HeapTupleIsValid(protup))
		elog(ERROR, "plecl: cache lookup failed for function %u", funcoid);
	proc = (Form_pg_proc) GETSTRUCT(protup);
	src = text_to_cstring_copy(SysCacheGetAttr(PROCOID, protup, Anum_pg_proc_prosrc, &isnull));
	if (isnull)
	{
		ReleaseSysCache(protup);
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("plecl: function has no source")));
	}
	boxed = plecl_funcall2("VALIDATE",
						   plecl_string(src, strlen(src)),
						   proc_arg_names(protup, proc->pronargs));
	ReleaseSysCache(protup);
	(void) unwrap_status(boxed, &payload);
	PG_RETURN_VOID();
}
