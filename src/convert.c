#include "plecl.h"

#include "utils/date.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"

static cl_object
keyword_from_attname(const char *name)
{
	char		buf[NAMEDATALEN];
	int			i;

	for (i = 0; name[i] && i < NAMEDATALEN - 1; i++)
		buf[i] = pg_ascii_toupper((unsigned char) name[i]);
	buf[i] = '\0';
	return ecl_make_keyword(buf);
}

static Size
utf8_decode1(const unsigned char *s, Size len, Size i, ecl_character *out)
{
	unsigned char	c0;

	if (i >= len)
	{
		*out = 0;
		return 0;
	}
	c0 = s[i];
	if (c0 < 0x80)
	{
		*out = (ecl_character) c0;
		return 1;
	}
	if (c0 < 0xC2 || c0 > 0xF4)
	{
		*out = (ecl_character) c0;
		return 1;
	}
	if (c0 < 0xE0)
	{
		if (i + 1 >= len || (s[i + 1] & 0xC0) != 0x80)
		{
			*out = (ecl_character) c0;
			return 1;
		}
		*out = ((ecl_character) (c0 & 0x1F) << 6) | (s[i + 1] & 0x3F);
		return 2;
	}
	if (c0 < 0xF0)
	{
		if (i + 2 >= len || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80)
		{
			*out = (ecl_character) c0;
			return 1;
		}
		*out = ((ecl_character) (c0 & 0x0F) << 12)
			| ((ecl_character) (s[i + 1] & 0x3F) << 6)
			| (s[i + 2] & 0x3F);
		return 3;
	}
	if (i + 3 >= len
		|| (s[i + 1] & 0xC0) != 0x80
		|| (s[i + 2] & 0xC0) != 0x80
		|| (s[i + 3] & 0xC0) != 0x80)
	{
		*out = (ecl_character) c0;
		return 1;
	}
	*out = ((ecl_character) (c0 & 0x07) << 18)
		| ((ecl_character) (s[i + 1] & 0x3F) << 12)
		| ((ecl_character) (s[i + 2] & 0x3F) << 6)
		| (s[i + 3] & 0x3F);
	return 4;
}

cl_object
plecl_string(const char *s, Size len)
{
	const unsigned char *p = (const unsigned char *) s;
	cl_object	str;
	cl_index	nchars = 0;
	Size		i;
	cl_index	k;

	if (s == NULL)
		return ECL_NIL;

	/* Ubuntu ECL has no ecl_decode_from_cstring. Base strings store bytes;
	   ecl_char then returns each UTF-8 unit and we double-encode on the way out. */
	for (i = 0; i < len; )
	{
		ecl_character	ch;
		Size			n = utf8_decode1(p, len, i, &ch);

		if (n == 0)
			break;
		i += n;
		nchars++;
	}
	str = cl_make_string(1, ecl_make_fixnum((cl_fixnum) nchars));
	for (i = 0, k = 0; k < nchars && i < len; k++)
	{
		ecl_character	ch;
		Size			n = utf8_decode1(p, len, i, &ch);

		if (n == 0)
			break;
		i += n;
		ecl_char_set(str, k, ch);
	}
	return str;
}

char *
plecl_cstring_palloc(cl_object obj)
{
	char	   *buf;
	cl_index	n;
	cl_index	i;
	cl_index	o = 0;

	if (plecl_sql_null_p(obj))
		return NULL;
	if (obj == ECL_NIL)
		return pstrdup("");
	if (!ECL_STRINGP(obj))
		obj = cl_princ_to_string(obj);

	/* ECL often keeps t_string (UTF-32). memcpy of fillp bytes yields one Latin char. */
	n = ecl_length(obj);
	buf = palloc(n * 4 + 1);
	for (i = 0; i < n; i++)
	{
		ecl_character	c = ecl_char(obj, i);

		if (c < 0x80)
			buf[o++] = (char) c;
		else if (c < 0x800)
		{
			buf[o++] = (char) (0xC0 | (c >> 6));
			buf[o++] = (char) (0x80 | (c & 0x3F));
		}
		else if (c < 0x10000)
		{
			buf[o++] = (char) (0xE0 | (c >> 12));
			buf[o++] = (char) (0x80 | ((c >> 6) & 0x3F));
			buf[o++] = (char) (0x80 | (c & 0x3F));
		}
		else
		{
			buf[o++] = (char) (0xF0 | (c >> 18));
			buf[o++] = (char) (0x80 | ((c >> 12) & 0x3F));
			buf[o++] = (char) (0x80 | ((c >> 6) & 0x3F));
			buf[o++] = (char) (0x80 | (c & 0x3F));
		}
	}
	buf[o] = '\0';
	return buf;
}

static cl_object
output_as_string(Oid typid, Datum d)
{
	Oid			typoutput;
	bool		typIsVarlena;
	char	   *s;

	getTypeOutputInfo(typid, &typoutput, &typIsVarlena);
	s = OidOutputFunctionCall(typoutput, d);
	return plecl_string(s, strlen(s));
}

static Datum
input_from_string(Oid typid, int32 typmod, const char *s)
{
	Oid			typinput;
	Oid			typioparam;

	getTypeInputInfo(typid, &typinput, &typioparam);
	return OidInputFunctionCall(typinput, pstrdup(s ? s : ""), typioparam, typmod);
}

static cl_object
array_to_list(Oid typid, Datum d)
{
	ArrayType  *arr = DatumGetArrayTypeP(d);
	Oid			elmtype = ARR_ELEMTYPE(arr);
	int16		elmlen;
	bool		elmbyval;
	char		elmalign;
	Datum	   *elems;
	bool	   *enulls;
	int			nelems;
	cl_object	list = ECL_NIL;
	int			i;

	get_typlenbyvalalign(elmtype, &elmlen, &elmbyval, &elmalign);
	deconstruct_array(arr, elmtype, elmlen, elmbyval, elmalign,
					  &elems, &enulls, &nelems);
	for (i = nelems - 1; i >= 0; i--)
		list = cl_cons(plecl_datum_to_object(elmtype, elems[i], enulls[i]), list);
	return list;
}

static Datum
list_to_array(Oid typid, int32 typmod, cl_object obj, bool *isnull)
{
	Oid			elmtype = get_element_type(typid);
	int16		elmlen;
	bool		elmbyval;
	char		elmalign;
	int			n;
	cl_object	c;
	int			i;
	Datum	   *elems;
	bool	   *enulls;
	int			dims[1];
	int			lbs[1];

	if (!OidIsValid(elmtype))
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("plecl: not an array type: %u", typid)));
	if (obj == ECL_NIL)
	{
		n = 0;
	}
	else if (ECL_LISTP(obj))
	{
		n = fixint(cl_length(obj));
	}
	else if (ECL_VECTORP(obj))
	{
		n = obj->vector.fillp;
	}
	else
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("plecl: array result must be a list or vector")));

	get_typlenbyvalalign(elmtype, &elmlen, &elmbyval, &elmalign);
	elems = (Datum *) palloc(sizeof(Datum) * Max(n, 1));
	enulls = (bool *) palloc(sizeof(bool) * Max(n, 1));

	if (ECL_VECTORP(obj) && !ECL_LISTP(obj))
	{
		for (i = 0; i < n; i++)
			elems[i] = plecl_object_to_datum(elmtype, typmod,
											 ecl_aref_unsafe(obj, i), &enulls[i]);
	}
	else
	{
		for (i = 0, c = obj; i < n; i++, c = ECL_CONS_CDR(c))
			elems[i] = plecl_object_to_datum(elmtype, typmod, ECL_CONS_CAR(c), &enulls[i]);
	}

	dims[0] = n;
	lbs[0] = 1;
	*isnull = false;
	return PointerGetDatum(construct_md_array(elems, enulls, 1, dims, lbs,
											  elmtype, elmlen, elmbyval, elmalign));
}

cl_object
plecl_tuple_to_object(HeapTuple tuple, TupleDesc tupdesc)
{
	cl_object	alist = ECL_NIL;
	int			i;

	for (i = 0; i < tupdesc->natts; i++)
	{
		Form_pg_attribute att = TupleDescAttr(tupdesc, i);
		bool		isnull;
		Datum		v;
		cl_object	pair;

		if (att->attisdropped)
			continue;
		v = heap_getattr(tuple, i + 1, tupdesc, &isnull);
		pair = cl_cons(keyword_from_attname(NameStr(att->attname)),
					   plecl_datum_to_object(att->atttypid, v, isnull));
		alist = cl_cons(pair, alist);
	}
	return cl_nreverse(alist);
}

HeapTuple
plecl_object_to_tuple(cl_object obj, TupleDesc tupdesc)
{
	int			natts = tupdesc->natts;
	Datum	   *values = (Datum *) palloc0(sizeof(Datum) * natts);
	bool	   *nulls = (bool *) palloc(sizeof(bool) * natts);
	int			i;

	memset(nulls, true, natts);
	if (!(obj == ECL_NIL || ECL_LISTP(obj)))
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("plecl: composite value must be an alist")));

	for (i = 0; i < natts; i++)
	{
		Form_pg_attribute att = TupleDescAttr(tupdesc, i);
		cl_object	key;
		cl_object	pair;

		if (att->attisdropped)
			continue;
		key = keyword_from_attname(NameStr(att->attname));
		pair = cl_assoc(2, key, obj);
		if (pair == ECL_NIL)
			nulls[i] = true;
		else
			values[i] = plecl_object_to_datum(att->atttypid, att->atttypmod,
											  ECL_CONS_CDR(pair), &nulls[i]);
	}
	return heap_form_tuple(tupdesc, values, nulls);
}

cl_object
plecl_datum_to_object(Oid typid, Datum d, bool isnull)
{
	if (isnull)
		return plecl_null_object();

	switch (typid)
	{
		case BOOLOID:
			return DatumGetBool(d) ? ECL_T : ECL_NIL;
		case INT2OID:
			return ecl_make_int32_t((int32) DatumGetInt16(d));
		case INT4OID:
			return ecl_make_int32_t(DatumGetInt32(d));
		case INT8OID:
			return ecl_make_int64_t(DatumGetInt64(d));
		case FLOAT4OID:
			return ecl_make_single_float(DatumGetFloat4(d));
		case FLOAT8OID:
			return ecl_make_double_float(DatumGetFloat8(d));
		case OIDOID:
			return ecl_make_uint32_t(DatumGetObjectId(d));
		case TEXTOID:
		case VARCHAROID:
		case BPCHAROID:
		case NAMEOID:
			{
				char	   *s = TextDatumGetCString(d);

				return plecl_string(s, strlen(s));
			}
		case CSTRINGOID:
			{
				char	   *s = DatumGetCString(d);

				return plecl_string(s, strlen(s));
			}
		case BYTEAOID:
			{
				bytea	   *b = DatumGetByteaPP(d);
				int			n = VARSIZE_ANY_EXHDR(b);
				cl_object	v = ecl_alloc_simple_vector(n, ecl_aet_b8);

				memcpy(v->vector.self.b8, VARDATA_ANY(b), n);
				v->vector.fillp = n;
				return v;
			}
		case VOIDOID:
			return ECL_NIL;
		default:
			break;
	}

	if (type_is_array(typid))
		return array_to_list(typid, d);

	if (type_is_rowtype(typid))
	{
		HeapTupleHeader td = DatumGetHeapTupleHeader(d);
		Oid			tupType;
		int32		tupTypmod;
		TupleDesc	tupdesc;
		HeapTupleData tmptup;

		tupType = HeapTupleHeaderGetTypeId(td);
		tupTypmod = HeapTupleHeaderGetTypMod(td);
		tupdesc = lookup_rowtype_tupdesc(tupType, tupTypmod);
		tmptup.t_len = HeapTupleHeaderGetDatumLength(td);
		tmptup.t_data = td;
		{
			cl_object	o = plecl_tuple_to_object(&tmptup, tupdesc);

			ReleaseTupleDesc(tupdesc);
			return o;
		}
	}

	return output_as_string(typid, d);
}

static bool
looks_like_number(cl_object obj)
{
	return ECL_FIXNUMP(obj) || ECL_BIGNUMP(obj) || ECL_SINGLE_FLOAT_P(obj)
		|| ECL_DOUBLE_FLOAT_P(obj) || ECL_LONG_FLOAT_P(obj)
		|| (!ECL_IMMEDIATE(obj) && obj->d.t == t_ratio);
}

Datum
plecl_object_to_datum(Oid typid, int32 typmod, cl_object obj, bool *isnull)
{
	*isnull = false;
	if (plecl_sql_null_p(obj))
	{
		*isnull = true;
		return (Datum) 0;
	}

	if (type_is_array(typid))
		return list_to_array(typid, typmod, obj, isnull);

	if (type_is_rowtype(typid))
	{
		TupleDesc	tupdesc = lookup_rowtype_tupdesc(typid, typmod);
		HeapTuple	tup = plecl_object_to_tuple(obj, tupdesc);
		Datum		d = HeapTupleGetDatum(tup);

		ReleaseTupleDesc(tupdesc);
		return d;
	}

	switch (typid)
	{
		case BOOLOID:
			return BoolGetDatum(obj != ECL_NIL);
		case INT2OID:
			return Int16GetDatum((int16) ecl_to_int32_t(obj));
		case INT4OID:
			return Int32GetDatum(ecl_to_int32_t(obj));
		case INT8OID:
			return Int64GetDatum(ecl_to_int64_t(obj));
		case FLOAT4OID:
			return Float4GetDatum((float4) ecl_to_double(obj));
		case FLOAT8OID:
			return Float8GetDatum(ecl_to_double(obj));
		case OIDOID:
			return ObjectIdGetDatum((Oid) ecl_to_uint32_t(obj));
		case TEXTOID:
		case VARCHAROID:
		case BPCHAROID:
			{
				char	   *s = plecl_cstring_palloc(obj);

				return CStringGetTextDatum(s ? s : "");
			}
		case NAMEOID:
			{
				char	   *s = plecl_cstring_palloc(obj);
				NameData	n;

				namestrcpy(&n, s ? s : "");
				return NameGetDatum(&n);
			}
		case CSTRINGOID:
			return CStringGetDatum(plecl_cstring_palloc(obj));
		case BYTEAOID:
			{
				int			n;
				bytea	   *b;

				if (ECL_VECTORP(obj))
				{
					n = obj->vector.fillp;
					b = (bytea *) palloc(VARHDRSZ + n);
					SET_VARSIZE(b, VARHDRSZ + n);
					if (ecl_array_elttype(obj) == ecl_aet_b8)
						memcpy(VARDATA(b), obj->vector.self.b8, n);
					else
					{
						int			i;

						for (i = 0; i < n; i++)
							((unsigned char *) VARDATA(b))[i] =
								(unsigned char) ecl_to_int32_t(ecl_aref_unsafe(obj, i));
					}
					return PointerGetDatum(b);
				}
				if (ECL_LISTP(obj) || obj == ECL_NIL)
				{
					n = (obj == ECL_NIL) ? 0 : fixint(cl_length(obj));
					b = (bytea *) palloc(VARHDRSZ + n);
					SET_VARSIZE(b, VARHDRSZ + n);
					{
						int			i;
						cl_object	c = obj;

						for (i = 0; i < n; i++, c = ECL_CONS_CDR(c))
							((unsigned char *) VARDATA(b))[i] =
								(unsigned char) ecl_to_int32_t(ECL_CONS_CAR(c));
					}
					return PointerGetDatum(b);
				}
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("plecl: bytea result must be a vector or list")));
				break;
			}
		case VOIDOID:
			*isnull = true;
			return (Datum) 0;
		default:
			break;
	}

	if (looks_like_number(obj) || ECL_STRINGP(obj) || obj == ECL_T || obj == ECL_NIL)
	{
		char	   *s = plecl_cstring_palloc(obj);

		return input_from_string(typid, typmod, s);
	}

	{
		char	   *s = plecl_cstring_palloc(cl_prin1_to_string(obj));

		return input_from_string(typid, typmod, s);
	}
}
