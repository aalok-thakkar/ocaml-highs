(lang dune 3.7)
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
Written in Jane Street style: module per type, records deriving \
sexp_of / compare / equal / hash / fields via ppx_jane, Or_error results \
for expected failures, an exception-throwing '_exn' companion for each \
Or_error function.\n\
\n\
Features in 0.1.0:\n\
- Immutable model type built from Var, Constraint, and Model modules.\n\
- Solve returning Solution.t Or_error.t (and solve_exn variant).\n\
- Typed options with an extras escape hatch keyed by option name.\n\
- File I/O to MPS / LP formats.\n\
- Inline expect tests covering every public entry point.\n\
\n\
Requires HiGHS 1.11 or later, discoverable via pkg-config.")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.7))
  dune-configurator
  (base (>= v0.17))
  (ppx_jane (>= v0.17))
  (core (and (>= v0.17) :with-test))
  (expect_test_helpers_core (and (>= v0.17) :with-test))
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
