(lang dune 3.0)
(name highs)
(version 0.1.0)

(generate_opam_files true)
(implicit_transitive_deps false)

(source (github aalok-thakkar/ocaml-highs))
(license MIT)
(authors "Aalok Thakkar")
(maintainers "Aalok Thakkar")
(documentation "https://aalok-thakkar.github.io/ocaml-highs")

(package
 (name highs)
 (synopsis
   "OCaml bindings for the HiGHS linear and mixed-integer optimization solver")
 (description
   "Idiomatic OCaml interface to HiGHS (https://highs.dev), an open-source \
solver for linear programming, mixed-integer programming, and quadratic \
programming from the University of Edinburgh.\n\
\n\
The binding is a thin, direct wrapper over the HiGHS C API. There is no \
intermediate C++ shim, so the stack is one FFI boundary instead of two: \
OCaml -> C stubs -> libhighs.\n\
\n\
Features in 0.1.0:\n\
- Bulk LP/MIP model passing plus incremental add_col/add_row.\n\
- Typed enums for objective sense, integrality, and model status.\n\
- Typed error module mirroring HighsStatus.\n\
- Typed common options (time limit, presolve, solver, parallel, mip_rel_gap, \
output flag) plus escape hatches for arbitrary options by name.\n\
- Solution readback: primal and dual values for columns and rows, objective \
value, model status.\n\
- File I/O: read .mps and .lp models, write models and solutions.\n\
- GC-managed handle lifetime via OCaml custom blocks and finalizers.\n\
\n\
Deferred to future releases: quadratic programming, callbacks, cutpools, \
presolve/postsolve pipelines, basis I/O.\n\
\n\
Requires HiGHS 1.11 or later, discoverable via pkg-config.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  dune-configurator
  (alcotest (and (>= 1.5) :with-test))
  (odoc :with-doc))
 (tags
  ("optimization"
   "solver"
   "linear-programming"
   "mixed-integer-programming"
   "operations-research"
   "milp"
   "lp"
   "highs")))
