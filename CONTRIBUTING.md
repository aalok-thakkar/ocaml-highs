# Contributing to ocaml-highs

## Project layout

```
src/
├── config/discover.ml     pkg-config probe
├── config/dune
├── dune
├── highs.ml + .mli        pure records + solve
└── highs_stubs.c          direct calls into highs_c_api.h

test/                       alcotest suite (real HiGHS backend)
examples/                   lp.ml, knapsack.ml
docs/design.md              lifetime, marshalling, status mapping notes
```

## Build

```sh
brew install highs                              # or apt-get install libhighs-dev
opam install . --deps-only --with-test
dune build
dune runtest
dune exec examples/knapsack.exe
```

If HiGHS is not in a standard pkg-config location:

```sh
export HIGHS_CFLAGS="-I/path/to/include"
export HIGHS_LIBS="-L/path/to/lib -lhighs"
```

## API guardrails

The public API is functional. New features should keep that.

- Model-building functions are pure OCaml. They return a `constr`,
  `var`, or `model` value; they never touch HiGHS.
- The only function that talks to HiGHS is `solve` (and `write`, which
  builds a temporary handle just for `Highs_writeModel`).
- Do not expose the internal `Ffi.handle` type. It is intentionally
  private.

If you find yourself wanting a "builder that mutates in place",
consider whether the same shape can be expressed as
`{ model with constraints = Array.append ... }`.

## Adding a new HiGHS entry point

For any new binding:

1. **`src/highs_stubs.c`**: add a `CAMLprim value caml_highs_...`
   function that calls the HiGHS C API. Use `check_status` on any
   `HighsInt` return code, or `check_status_with_key` if the operation
   has an offending key or path worth surfacing in the error message.
2. **`src/highs.ml`**: declare an `external` inside the private `Ffi`
   module. Extend the public `solve` (or add a new pure function) so
   the FFI stays hidden.
3. **`src/highs.mli`**: document the new public function or record
   field.

If the HiGHS call takes an OCaml `int array` and needs `HighsInt*`, use
`alloc_hi_from_ocaml_intarr`. Remember to `caml_stat_free` the buffer.

## Testing

Every new feature gets at least one alcotest case in
`test/test_highs.ml`. Group by area:

- `constructors` for pure OCaml constructors
- `lp` / `mip` for solve behavior
- `status` for status outcomes
- `options` for option handling
- `file_io` for read/write

## HiGHS version compatibility

HiGHS grows its C API but does not remove entry points. New releases
mean new bindings we can add; existing bindings continue to work. When
a HiGHS release adds a useful entry point, add the binding and note
the minimum required version in the CHANGELOG.

## Commit style

[Conventional Commits](https://www.conventionalcommits.org/):
```
feat: bind Highs_passHessian for QP
fix(stubs): include option key in Solver_error message
docs: clarify functional-core / imperative-shell boundary
test: cover Warning status separately from Ok
```
