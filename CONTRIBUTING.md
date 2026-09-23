# Contributing to ocaml-highs

## Project layout

```
src/
├── config/discover.ml     pkg-config probe
├── config/dune
├── dune
├── highs.ml + .mli        module-per-type API + derivers via ppx_jane
└── highs_stubs.c          direct calls into highs_c_api.h

test/                       inline expect tests (ppx_expect via ppx_jane)
examples/                   lp.ml, knapsack.ml
docs/design.md              lifetime, marshalling, module structure notes
```

## Build

```sh
brew install highs                              # or apt-get install libhighs-dev
opam install . --deps-only --with-test
dune build
dune runtest
dune exec examples/knapsack.exe
```

If HiGHS is in a non-standard location:

```sh
export HIGHS_CFLAGS="-I/path/to/include"
export HIGHS_LIBS="-L/path/to/lib -lhighs"
```

## Style

Jane Street conventions:

- Each type gets its own module with `type t` as the primary type.
- Every record derives `sexp_of, compare, equal` (and `fields` where
  useful) via `ppx_jane`.
- Recoverable failures return `_ Or_error.t`. Exception-throwing
  companions have the `_exn` suffix.
- `open Base` (or `Core` in tests) rather than stdlib functions.
- Format with `ocamlformat` (config in `.ocamlformat`).

## Adding a new HiGHS entry point

1. **`src/highs_stubs.c`**: add a `CAMLprim value caml_highs_...` that
   calls the HiGHS C API. Use `check_status_with_key` for calls that
   have a natural key or path to include in the error message.
2. **`src/highs.ml`**: declare an `external` inside the private `Ffi`
   module; extend `solve`/`write` or add a new pure function.
3. **`src/highs.mli`**: document the new public function.

If the HiGHS call takes an OCaml `int array` and needs `HighsInt*`, use
`alloc_hi_buf`. Remember to `caml_stat_free` the buffer.

## Adding a new record type

1. Declare the record inside its own module.
2. Add `[@@deriving sexp_of, compare, equal, fields]`.
3. Provide a `create` function with labeled args and reasonable defaults.
4. If the type has bounded semantics (e.g. binary vars with implicit
   `[0, 1]` bounds), add a helper constructor that hides the invariant.

## Testing

Every new feature gets a `let%expect_test` block in
`test/test_highs.ml`. Print via `print_s [%sexp (x : ...)]` for
structural comparison against `[%expect]`. When output changes, `dune
promote` accepts the new baseline.

## Commit style

[Conventional Commits](https://www.conventionalcommits.org/):
```
feat: bind Highs_passHessian for QP
fix(stubs): include option key in Solver_error
docs: clarify Or_error vs _exn conventions
test: cover Warning status separately from Ok
```
