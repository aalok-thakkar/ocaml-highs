# Design notes: ocaml-highs

## Three-layer stack

```
user code (pure OCaml)
   │
   │  builds a value of type [Highs.model]
   ▼
Highs.solve                            the only side-effect
   │  encodes model into HiGHS arrays
   ▼
highs_stubs.c                          OCaml C stubs
   │  direct calls to the HiGHS C API
   ▼
libhighs                               MIT-licensed C++ solver
```

Because HiGHS ships a documented C API (`interfaces/highs_c_api.h`),
this binding needs no intermediate `extern "C"` shim. Compare with
[ocaml-hexaly], where the underlying solver is C++-only and a fourth
layer bridges the C++ classes to a C ABI.

[ocaml-hexaly]: https://github.com/aalok-thakkar/ocaml-hexaly

## Functional core, imperative shell

HiGHS itself is stateful: a `Highs*` handle mutates as you add columns,
set options, and run. The OCaml binding hides all of that. From the
user's perspective:

- Everything you build with `var`, `continuous`, `integer`, `binary`,
  `eq`, `leq`, `geq`, `range`, `model`, `default_options` is a pure
  record.
- `solve : ?options:options -> model -> solution` is the sole
  side-effect. It allocates a handle, encodes the model, runs the
  solver, reads back the answer, and releases the handle before
  returning.

The internal encoding function in `highs.ml` walks the constraints once
to compute the total number of non-zeros, then a second time to fill
the CSR arrays HiGHS expects (`a_start`, `a_index`, `a_value`). Both
passes run before HiGHS touches the data.

## Why an immutable model is the right default

- **Composable.** Two functions that each produce a `model` can be
  glued together with `{ m with constraints = Array.append ... }`
  without any risk of double-mutation.
- **Testable.** The encoder is a pure function from `model` to
  `(a_start, a_index, a_value)`. You can write property-based tests
  for it without a HiGHS handle.
- **Debuggable.** A `model` is a value you can print, compare, save to
  disk, or pass around freely.
- **Reproducible.** `solve m` is referentially transparent modulo
  solver options that affect randomness (`random_seed`).

The trade-off is peak memory: for a large model, the immutable
`vars` and `constraints` arrays live alongside HiGHS's own arrays during
`solve`. If you have a 10M-variable LP, that is real memory pressure.
For any model that fits comfortably in RAM twice, this design is
worth it.

## Handle lifetime

The HiGHS handle is a `void*` wrapped in an OCaml custom block. The
block's finalizer calls `Highs_destroy` when the OCaml value becomes
unreachable. `solve` binds the handle to a local; after `solve`
returns, the local is unreachable and GC will eventually finalize it.
For typical use (solve rate under thousands per second) this is fine.

## HighsInt marshalling

HiGHS builds with either `int` or `int64_t` as `HighsInt` (compile-time
`HIGHSINT64` switch). Homebrew and Debian builds use `int`. Our C
stubs include `highs_c_api.h` so they see whichever type the local
HiGHS install was built with.

When we pass an OCaml `int array` to a HiGHS function that expects
`HighsInt*`, we allocate a converted buffer with `caml_stat_alloc` and
free it after the call. This is the price for supporting both build
flavors transparently.

## Float array marshalling

OCaml's `float array` on 64-bit platforms uses `Double_array_tag`,
which stores raw `double` values contiguously. We pass the array
pointer directly to HiGHS with `(const double*)v_array`; no copy. This
matters for large LPs with many non-zeros.

## Status mapping

HiGHS has two enums: `HighsStatus` (Ok / Warning / Error) for individual
call outcomes, and `HighsModelStatus` (17 values) for the outcome of a
solve. The binding folds both into one user-facing `Highs.status`
type. The rare `HighsModelStatus` values (`ObjectiveBound`,
`ObjectiveTarget`, `SolutionLimit`, `Unknown`) map to
`Other of string` so we don't inflate the variant with rarely-used
cases.

## Options: typed common, untyped extras

Common options have typed fields on the `options` record. Anything else
goes through `extra`, a `(string * option_value) list`. This is the
smallest total API surface that covers HiGHS's option catalog without
locking us into changes when HiGHS adds new options.

The C stub includes the offending option name in the raised
`Solver_error` message on failure, so a typo (`"threds"` instead of
`"threads"`) reports itself clearly.

## What's not bound in 0.1

- **QP.** `Highs_passHessian` and friends. Straightforward extension.
- **Callbacks.** Would need a trampoline that acquires the OCaml
  runtime lock; see ocaml-hexaly for the pattern.
- **`read : string -> model`.** Reading an MPS/LP file into a pure
  `model` value requires walking HiGHS's `getCols` / `getRows` after
  `readModel`. Doable, not yet done. `write` works because writing is
  a straight-through call.
- **Basis I/O**, **cutpool exposure**, **presolve/postsolve details**.
