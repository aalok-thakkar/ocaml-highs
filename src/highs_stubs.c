/* OCaml C stubs over HiGHS's public C API. The single opaque handle is a
 * void* wrapped in a custom block whose finalizer calls Highs_destroy.
 * HighsStatus Error return codes raise Highs.Solver_error, with the
 * offending option key or file path folded into the message when useful. */
#define CAML_NAME_SPACE
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "interfaces/highs_c_api.h"

/* -- Error raising --------------------------------------------------- */

static const value* solver_error_exn = NULL;

static void raise_solver_error(const char* msg) {
    if (solver_error_exn == NULL)
        solver_error_exn = caml_named_value("Highs.Solver_error");
    if (solver_error_exn == NULL) caml_failwith(msg);
    caml_raise_with_string(*solver_error_exn, msg);
}

static void check_status(HighsInt rc, const char* op) {
    if (rc == kHighsStatusError) raise_solver_error(op);
}

static void check_status_with_key(HighsInt rc, const char* op, const char* key) {
    if (rc != kHighsStatusError) return;
    char buf[256];
    snprintf(buf, sizeof(buf), "%s: %s", op, key ? key : "(null)");
    raise_solver_error(buf);
}

/* -- Handle custom block --------------------------------------------- */

static void hs_finalize(value v) {
    void* h = *((void**)Data_custom_val(v));
    if (h) Highs_destroy(h);
}

static struct custom_operations hs_ops = {
    "highs.handle",
    hs_finalize,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

static value hs_alloc(void* h) {
    value v = caml_alloc_custom(&hs_ops, sizeof(void*), 0, 1);
    *((void**)Data_custom_val(v)) = h;
    return v;
}

static inline void* hs_get(value v) {
    return *((void**)Data_custom_val(v));
}

/* HighsInt is int or int64_t depending on how HiGHS was built. When
 * receiving an OCaml int array we allocate a converted buffer. */
static HighsInt* alloc_hi_buf(value v, int* out_n) {
    mlsize_t n = Wosize_val(v);
    *out_n = (int)n;
    if (n == 0) return NULL;
    HighsInt* buf = (HighsInt*)caml_stat_alloc(n * sizeof(HighsInt));
    for (mlsize_t i = 0; i < n; ++i) buf[i] = (HighsInt)Long_val(Field(v, i));
    return buf;
}

/* -- Version --------------------------------------------------------- */

CAMLprim value caml_highs_version       (value u) { (void)u; return caml_copy_string(Highs_version()); }
CAMLprim value caml_highs_version_major (value u) { (void)u; return Val_int((int)Highs_versionMajor()); }
CAMLprim value caml_highs_version_minor (value u) { (void)u; return Val_int((int)Highs_versionMinor()); }
CAMLprim value caml_highs_version_patch (value u) { (void)u; return Val_int((int)Highs_versionPatch()); }
CAMLprim value caml_highs_githash       (value u) { (void)u; return caml_copy_string(Highs_githash()); }

/* -- Lifecycle ------------------------------------------------------- */

CAMLprim value caml_highs_create(value unit) {
    CAMLparam1(unit);
    void* h = Highs_create();
    if (h == NULL) raise_solver_error("Highs.create: allocation failed");
    CAMLreturn(hs_alloc(h));
}

/* -- Run ------------------------------------------------------------- */

CAMLprim value caml_highs_run(value v) {
    CAMLparam1(v);
    HighsInt rc = Highs_run(hs_get(v));
    CAMLreturn(Val_int((int)rc));
}

CAMLprim value caml_highs_get_model_status(value v) {
    CAMLparam1(v);
    CAMLreturn(Val_int((int)Highs_getModelStatus(hs_get(v))));
}

CAMLprim value caml_highs_get_objective_value(value v) {
    CAMLparam1(v);
    CAMLreturn(caml_copy_double(Highs_getObjectiveValue(hs_get(v))));
}

/* -- Bulk model loading --------------------------------------------- */

CAMLprim value caml_highs_pass_lp_bytecode(value* argv, int argn);

CAMLprim value caml_highs_pass_lp_native(
    value v_h, value v_sense, value v_offset,
    value v_cost, value v_col_l, value v_col_u,
    value v_row_l, value v_row_u,
    value v_a_start, value v_a_index, value v_a_value,
    value v_a_format)
{
    CAMLparam5(v_h, v_sense, v_offset, v_cost, v_col_l);
    CAMLxparam5(v_col_u, v_row_l, v_row_u, v_a_start, v_a_index);
    CAMLxparam2(v_a_value, v_a_format);

    int num_col = (int)Wosize_val(v_cost);
    int num_row = (int)Wosize_val(v_row_l);
    int a_start_n, a_index_n;
    HighsInt* a_start = alloc_hi_buf(v_a_start, &a_start_n);
    HighsInt* a_index = alloc_hi_buf(v_a_index, &a_index_n);
    (void)a_start_n;

    HighsInt rc = Highs_passLp(
        hs_get(v_h),
        (HighsInt)num_col, (HighsInt)num_row, (HighsInt)a_index_n,
        (HighsInt)Int_val(v_a_format),
        (HighsInt)Int_val(v_sense),
        Double_val(v_offset),
        (const double*)v_cost, (const double*)v_col_l, (const double*)v_col_u,
        (const double*)v_row_l, (const double*)v_row_u,
        a_start, a_index, (const double*)v_a_value);

    caml_stat_free(a_start);
    caml_stat_free(a_index);
    check_status(rc, "Highs.pass_lp");
    CAMLreturn(Val_unit);
}

CAMLprim value caml_highs_pass_lp_bytecode(value* argv, int argn) {
    (void)argn;
    return caml_highs_pass_lp_native(
        argv[0], argv[1], argv[2], argv[3], argv[4],
        argv[5], argv[6], argv[7], argv[8], argv[9],
        argv[10], argv[11]);
}

CAMLprim value caml_highs_pass_mip_bytecode(value* argv, int argn);

CAMLprim value caml_highs_pass_mip_native(
    value v_h, value v_sense, value v_offset,
    value v_cost, value v_col_l, value v_col_u,
    value v_row_l, value v_row_u,
    value v_a_start, value v_a_index, value v_a_value,
    value v_a_format, value v_integ)
{
    CAMLparam5(v_h, v_sense, v_offset, v_cost, v_col_l);
    CAMLxparam5(v_col_u, v_row_l, v_row_u, v_a_start, v_a_index);
    CAMLxparam3(v_a_value, v_a_format, v_integ);

    int num_col = (int)Wosize_val(v_cost);
    int num_row = (int)Wosize_val(v_row_l);
    int a_start_n, a_index_n, integ_n;
    HighsInt* a_start = alloc_hi_buf(v_a_start, &a_start_n);
    HighsInt* a_index = alloc_hi_buf(v_a_index, &a_index_n);
    HighsInt* integ   = alloc_hi_buf(v_integ,   &integ_n);
    (void)a_start_n; (void)integ_n;

    HighsInt rc = Highs_passMip(
        hs_get(v_h),
        (HighsInt)num_col, (HighsInt)num_row, (HighsInt)a_index_n,
        (HighsInt)Int_val(v_a_format),
        (HighsInt)Int_val(v_sense),
        Double_val(v_offset),
        (const double*)v_cost, (const double*)v_col_l, (const double*)v_col_u,
        (const double*)v_row_l, (const double*)v_row_u,
        a_start, a_index, (const double*)v_a_value,
        integ);

    caml_stat_free(a_start);
    caml_stat_free(a_index);
    caml_stat_free(integ);
    check_status(rc, "Highs.pass_mip");
    CAMLreturn(Val_unit);
}

CAMLprim value caml_highs_pass_mip_bytecode(value* argv, int argn) {
    (void)argn;
    return caml_highs_pass_mip_native(
        argv[0], argv[1], argv[2], argv[3], argv[4],
        argv[5], argv[6], argv[7], argv[8], argv[9],
        argv[10], argv[11], argv[12]);
}

/* -- Options -------------------------------------------------------- */

CAMLprim value caml_highs_set_bool_option(value v_h, value v_key, value v_val) {
    CAMLparam3(v_h, v_key, v_val);
    const char* key = String_val(v_key);
    check_status_with_key(
        Highs_setBoolOptionValue(hs_get(v_h), key, (HighsInt)Bool_val(v_val)),
        "set option (bool)", key);
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_set_int_option(value v_h, value v_key, value v_val) {
    CAMLparam3(v_h, v_key, v_val);
    const char* key = String_val(v_key);
    check_status_with_key(
        Highs_setIntOptionValue(hs_get(v_h), key, (HighsInt)Long_val(v_val)),
        "set option (int)", key);
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_set_double_option(value v_h, value v_key, value v_val) {
    CAMLparam3(v_h, v_key, v_val);
    const char* key = String_val(v_key);
    check_status_with_key(
        Highs_setDoubleOptionValue(hs_get(v_h), key, Double_val(v_val)),
        "set option (double)", key);
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_set_string_option(value v_h, value v_key, value v_val) {
    CAMLparam3(v_h, v_key, v_val);
    const char* key = String_val(v_key);
    check_status_with_key(
        Highs_setStringOptionValue(hs_get(v_h), key, String_val(v_val)),
        "set option (string)", key);
    CAMLreturn(Val_unit);
}

/* -- Solution -------------------------------------------------------- */

CAMLprim value caml_highs_get_solution(value v_h) {
    CAMLparam1(v_h);
    CAMLlocal5(tuple, v_cv, v_cd, v_rv, v_rd);
    void* h = hs_get(v_h);
    intnat nc = (intnat)Highs_getNumCol(h);
    intnat nr = (intnat)Highs_getNumRow(h);
    v_cv = caml_alloc(nc, Double_array_tag);
    v_cd = caml_alloc(nc, Double_array_tag);
    v_rv = caml_alloc(nr, Double_array_tag);
    v_rd = caml_alloc(nr, Double_array_tag);
    HighsInt rc = Highs_getSolution(h,
        (double*)v_cv, (double*)v_cd, (double*)v_rv, (double*)v_rd);
    check_status(rc, "Highs.solution");
    tuple = caml_alloc(4, 0);
    Store_field(tuple, 0, v_cv);
    Store_field(tuple, 1, v_cd);
    Store_field(tuple, 2, v_rv);
    Store_field(tuple, 3, v_rd);
    CAMLreturn(tuple);
}

/* -- Info values ---------------------------------------------------- */

CAMLprim value caml_highs_get_int64_info(value v_h, value v_key) {
    CAMLparam2(v_h, v_key);
    int64_t out = 0;
    check_status(
        Highs_getInt64InfoValue(hs_get(v_h), String_val(v_key), &out),
        "Highs.int64_info");
    CAMLreturn(caml_copy_int64(out));
}

/* -- File I/O ------------------------------------------------------- */

CAMLprim value caml_highs_write_model(value v_h, value v_path) {
    CAMLparam2(v_h, v_path);
    const char* path = String_val(v_path);
    check_status_with_key(Highs_writeModel(hs_get(v_h), path),
                          "write model", path);
    CAMLreturn(Val_unit);
}
