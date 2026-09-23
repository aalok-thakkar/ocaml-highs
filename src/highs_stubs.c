/* highs_stubs.c - OCaml C stubs over highs_c_api.h.
 *
 * The HiGHS handle (opaque void*) is wrapped in an OCaml custom block whose
 * finalizer calls Highs_destroy. Any HiGHS entry point that returns
 * HighsStatus is checked: error status raises Highs_error, warning status
 * returns cleanly.
 */
#define CAML_NAME_SPACE
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>

#include <stdlib.h>
#include <string.h>

#include "interfaces/highs_c_api.h"

/* ---------- typed error raising ---------- */
static const value* highs_error_exn = NULL;

static void init_highs_error_exn(void) {
    if (highs_error_exn == NULL) {
        highs_error_exn = caml_named_value("Highs.Solver_error");
    }
}

static void raise_highs_error(const char* msg) {
    init_highs_error_exn();
    if (highs_error_exn == NULL) caml_failwith(msg);
    caml_raise_with_string(*highs_error_exn, msg);
}

/* HighsStatus: Ok=0, Warning=1, Error=-1. Error raises. */
static void check_status(HighsInt rc, const char* where) {
    if (rc == kHighsStatusError) raise_highs_error(where);
}

/* Same but includes an offending key or path in the message. Caller must
 * ensure [key] is a valid C string; buf sized for the compound message. */
static void check_status_with_key(HighsInt rc, const char* op, const char* key) {
    if (rc != kHighsStatusError) return;
    char buf[256];
    snprintf(buf, sizeof(buf), "%s: %s", op, key ? key : "(null)");
    raise_highs_error(buf);
}

/* ---------- custom block for the void* handle ---------- */
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

/* ---------- HighsInt marshalling ----------
 * HighsInt is either 'int' or 'int64_t' depending on how HiGHS was built.
 * We allocate a converted buffer when passing OCaml int arrays into C. */
static HighsInt* alloc_hi_from_ocaml_intarr(value v, int* out_n) {
    mlsize_t n = Wosize_val(v);
    *out_n = (int)n;
    if (n == 0) return NULL;
    HighsInt* buf = (HighsInt*)caml_stat_alloc(n * sizeof(HighsInt));
    for (mlsize_t i = 0; i < n; ++i) buf[i] = (HighsInt)Long_val(Field(v, i));
    return buf;
}

/* ---------- Version ---------- */
CAMLprim value caml_highs_version(value unit) {
    (void)unit;
    return caml_copy_string(Highs_version());
}
CAMLprim value caml_highs_version_major(value unit) { (void)unit; return Val_int((int)Highs_versionMajor()); }
CAMLprim value caml_highs_version_minor(value unit) { (void)unit; return Val_int((int)Highs_versionMinor()); }
CAMLprim value caml_highs_version_patch(value unit) { (void)unit; return Val_int((int)Highs_versionPatch()); }
CAMLprim value caml_highs_githash(value unit) {
    (void)unit;
    return caml_copy_string(Highs_githash());
}

/* ---------- Lifecycle ---------- */
CAMLprim value caml_highs_create(value unit) {
    CAMLparam1(unit);
    void* h = Highs_create();
    if (h == NULL) raise_highs_error("Highs.create: allocation failed");
    CAMLreturn(hs_alloc(h));
}

CAMLprim value caml_highs_clear(value v) {
    CAMLparam1(v);
    check_status(Highs_clear(hs_get(v)), "Highs.clear");
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_clear_model(value v) {
    CAMLparam1(v);
    check_status(Highs_clearModel(hs_get(v)), "Highs.clear_model");
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_clear_solver(value v) {
    CAMLparam1(v);
    check_status(Highs_clearSolver(hs_get(v)), "Highs.clear_solver");
    CAMLreturn(Val_unit);
}

/* ---------- Run ---------- */
CAMLprim value caml_highs_run(value v) {
    CAMLparam1(v);
    /* Return the raw HighsStatus so OCaml can pattern-match Ok/Warning.
     * Error is raised inside check_status only in build/getter paths;
     * run() itself can validly return Error and we surface it as a value. */
    HighsInt rc = Highs_run(hs_get(v));
    CAMLreturn(Val_int((int)rc));
}

/* ---------- Sense / integrality / model status ---------- */
CAMLprim value caml_highs_change_objective_sense(value v_h, value v_sense) {
    CAMLparam2(v_h, v_sense);
    check_status(
        Highs_changeObjectiveSense(hs_get(v_h), (HighsInt)Int_val(v_sense)),
        "Highs.change_objective_sense");
    CAMLreturn(Val_unit);
}

CAMLprim value caml_highs_change_col_integrality(value v_h, value v_col, value v_i) {
    CAMLparam3(v_h, v_col, v_i);
    check_status(
        Highs_changeColIntegrality(hs_get(v_h),
                                    (HighsInt)Long_val(v_col),
                                    (HighsInt)Int_val(v_i)),
        "Highs.change_col_integrality");
    CAMLreturn(Val_unit);
}

CAMLprim value caml_highs_get_model_status(value v) {
    CAMLparam1(v);
    CAMLreturn(Val_int((int)Highs_getModelStatus(hs_get(v))));
}

CAMLprim value caml_highs_get_num_col(value v) {
    CAMLparam1(v);
    CAMLreturn(Val_long((intnat)Highs_getNumCol(hs_get(v))));
}

CAMLprim value caml_highs_get_num_row(value v) {
    CAMLparam1(v);
    CAMLreturn(Val_long((intnat)Highs_getNumRow(hs_get(v))));
}

CAMLprim value caml_highs_get_objective_value(value v) {
    CAMLparam1(v);
    CAMLreturn(caml_copy_double(Highs_getObjectiveValue(hs_get(v))));
}

/* ---------- Bulk LP / MIP load ---------- */
/* Args: h, sense, offset, col_cost, col_lower, col_upper, row_lower,
 * row_upper, a_start, a_index, a_value, a_format */
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

    int num_col = (int)(Wosize_val(v_cost));
    int num_row = (int)(Wosize_val(v_row_l));
    int nz;
    int a_index_n;
    HighsInt* a_start = alloc_hi_from_ocaml_intarr(v_a_start, &nz);
    HighsInt* a_index = alloc_hi_from_ocaml_intarr(v_a_index, &a_index_n);
    int num_nz = a_index_n;
    (void)nz;

    const double* col_cost = (const double*)v_cost;
    const double* col_l    = (const double*)v_col_l;
    const double* col_u    = (const double*)v_col_u;
    const double* row_l    = (const double*)v_row_l;
    const double* row_u    = (const double*)v_row_u;
    const double* a_value  = (const double*)v_a_value;

    HighsInt rc = Highs_passLp(
        hs_get(v_h),
        (HighsInt)num_col, (HighsInt)num_row, (HighsInt)num_nz,
        (HighsInt)Int_val(v_a_format),
        (HighsInt)Int_val(v_sense),
        Double_val(v_offset),
        col_cost, col_l, col_u, row_l, row_u,
        a_start, a_index, a_value);

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

/* Highs_passMip: same signature plus a per-column integrality array. */
CAMLprim value caml_highs_pass_mip_bytecode(value* argv, int argn);

CAMLprim value caml_highs_pass_mip_native(
    value v_h, value v_sense, value v_offset,
    value v_cost, value v_col_l, value v_col_u,
    value v_row_l, value v_row_u,
    value v_a_start, value v_a_index, value v_a_value,
    value v_a_format, value v_integrality)
{
    CAMLparam5(v_h, v_sense, v_offset, v_cost, v_col_l);
    CAMLxparam5(v_col_u, v_row_l, v_row_u, v_a_start, v_a_index);
    CAMLxparam3(v_a_value, v_a_format, v_integrality);

    int num_col = (int)(Wosize_val(v_cost));
    int num_row = (int)(Wosize_val(v_row_l));
    int a_index_n, a_start_n, integ_n;
    HighsInt* a_start = alloc_hi_from_ocaml_intarr(v_a_start, &a_start_n);
    HighsInt* a_index = alloc_hi_from_ocaml_intarr(v_a_index, &a_index_n);
    HighsInt* integ   = alloc_hi_from_ocaml_intarr(v_integrality, &integ_n);
    int num_nz = a_index_n;
    (void)a_start_n; (void)integ_n;

    const double* col_cost = (const double*)v_cost;
    const double* col_l    = (const double*)v_col_l;
    const double* col_u    = (const double*)v_col_u;
    const double* row_l    = (const double*)v_row_l;
    const double* row_u    = (const double*)v_row_u;
    const double* a_value  = (const double*)v_a_value;

    HighsInt rc = Highs_passMip(
        hs_get(v_h),
        (HighsInt)num_col, (HighsInt)num_row, (HighsInt)num_nz,
        (HighsInt)Int_val(v_a_format),
        (HighsInt)Int_val(v_sense),
        Double_val(v_offset),
        col_cost, col_l, col_u, row_l, row_u,
        a_start, a_index, a_value,
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

/* ---------- Incremental building ---------- */
CAMLprim value caml_highs_add_col(value v_h, value v_cost, value v_lo, value v_hi,
                                   value v_idx, value v_val) {
    CAMLparam5(v_h, v_cost, v_lo, v_hi, v_idx);
    CAMLxparam1(v_val);
    int n;
    HighsInt* idx = alloc_hi_from_ocaml_intarr(v_idx, &n);
    const double* val = (const double*)v_val;
    HighsInt rc = Highs_addCol(hs_get(v_h),
                                Double_val(v_cost), Double_val(v_lo), Double_val(v_hi),
                                (HighsInt)n, idx, val);
    caml_stat_free(idx);
    check_status(rc, "Highs.add_col");
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_add_col_bytecode(value* argv, int argn) {
    (void)argn;
    return caml_highs_add_col(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

CAMLprim value caml_highs_add_row(value v_h, value v_lo, value v_hi,
                                   value v_idx, value v_val) {
    CAMLparam5(v_h, v_lo, v_hi, v_idx, v_val);
    int n;
    HighsInt* idx = alloc_hi_from_ocaml_intarr(v_idx, &n);
    const double* val = (const double*)v_val;
    HighsInt rc = Highs_addRow(hs_get(v_h),
                                Double_val(v_lo), Double_val(v_hi),
                                (HighsInt)n, idx, val);
    caml_stat_free(idx);
    check_status(rc, "Highs.add_row");
    CAMLreturn(Val_unit);
}

/* ---------- Options ---------- */
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

/* ---------- Solution ---------- */
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
                                     (double*)v_cv, (double*)v_cd,
                                     (double*)v_rv, (double*)v_rd);
    check_status(rc, "Highs.solution");
    tuple = caml_alloc(4, 0);
    Store_field(tuple, 0, v_cv);
    Store_field(tuple, 1, v_cd);
    Store_field(tuple, 2, v_rv);
    Store_field(tuple, 3, v_rd);
    CAMLreturn(tuple);
}

/* ---------- File I/O ---------- */
CAMLprim value caml_highs_read_model(value v_h, value v_path) {
    CAMLparam2(v_h, v_path);
    const char* path = String_val(v_path);
    check_status_with_key(Highs_readModel(hs_get(v_h), path),
                          "read model", path);
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_write_model(value v_h, value v_path) {
    CAMLparam2(v_h, v_path);
    const char* path = String_val(v_path);
    check_status_with_key(Highs_writeModel(hs_get(v_h), path),
                          "write model", path);
    CAMLreturn(Val_unit);
}
CAMLprim value caml_highs_write_solution(value v_h, value v_path) {
    CAMLparam2(v_h, v_path);
    const char* path = String_val(v_path);
    check_status_with_key(Highs_writeSolution(hs_get(v_h), path),
                          "write solution", path);
    CAMLreturn(Val_unit);
}

/* ---------- Info values (int, int64, double) ---------- */
CAMLprim value caml_highs_get_int_info(value v_h, value v_key) {
    CAMLparam2(v_h, v_key);
    HighsInt out = 0;
    check_status(
        Highs_getIntInfoValue(hs_get(v_h), String_val(v_key), &out),
        "Highs.int_info");
    CAMLreturn(Val_long((intnat)out));
}

CAMLprim value caml_highs_get_int64_info(value v_h, value v_key) {
    CAMLparam2(v_h, v_key);
    int64_t out = 0;
    check_status(
        Highs_getInt64InfoValue(hs_get(v_h), String_val(v_key), &out),
        "Highs.int64_info");
    CAMLreturn(caml_copy_int64(out));
}

CAMLprim value caml_highs_get_double_info(value v_h, value v_key) {
    CAMLparam2(v_h, v_key);
    double out = 0.0;
    check_status(
        Highs_getDoubleInfoValue(hs_get(v_h), String_val(v_key), &out),
        "Highs.double_info");
    CAMLreturn(caml_copy_double(out));
}
