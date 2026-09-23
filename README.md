# highs

[![opam](https://img.shields.io/badge/opam-highs-blue)](https://opam.ocaml.org/packages/highs/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

OCaml bindings for **[HiGHS](https://highs.dev)**, the open-source
linear, mixed-integer, and quadratic programming solver from the
University of Edinburgh.

Written in Jane Street style: module per type, records deriving
`sexp_of` / `compare` / `equal` / `hash` / `fields` via `ppx_jane`,
`Or_error.t` results for expected failures with `_exn` companions.

```ocaml
open Core
open Highs

let m =
  Model.create
    ~sense:Minimize
    ~vars:[|
      Var.continuous ~name:"bread" ~cost:0.5 ();
      Var.continuous ~name:"milk"  ~cost:0.3 ();
      Var.continuous ~name:"meat"  ~cost:0.7 ();
    |]
    ~constraints:[|
      Constraint.geq ~name:"protein"
        ~terms:[(4., 0); (8., 1); (20., 2)] ~rhs:50. ();
      Constraint.geq ~name:"calcium"
        ~terms:[(2., 0); (12., 1); (3., 2)] ~rhs:30. ();
    |]
    ()

let () =
  match solve m with
  | Ok sol ->
    print_s [%sexp (sol.status : Status.t)];
    printf "cost = %.4f\n" sol.objective
  | Error e -> print_s [%sexp (e : Error.t)]
```

## Design

Everything the user builds is a pure record from a named module:
`Sense.t`, `Var_kind.t`, `Var.t`, `Term.t`, `Constraint.t`, `Model.t`,
`Solver_algorithm.t`, `Toggle.t`, `Option_value.t`, `Options.t`,
`Status.t`, `Solution.t`. Every record type derives `sexp_of`,
`compare`, `equal` (and `fields` where useful) so you can print,
diff, hash, and traverse them with ppx-generated helpers.

`solve : ?options:Options.t -> Model.t -> Solution.t Or_error.t` and
`write : ?options -> Model.t -> string -> unit Or_error.t` are the only
functions that talk to HiGHS. Both have `_exn` companions
(`solve_exn`, `write_exn`) that raise `Solver_error` instead of
returning `Error`, following Jane Street's `_exn` convention for
functions that fail rarely.

## Installation

```sh
opam install highs
```

The binding needs HiGHS on your system. Package managers:

| OS               | Command                             |
| ---------------- | ----------------------------------- |
| macOS (homebrew) | `brew install highs`                |
| Debian / Ubuntu  | `apt-get install libhighs-dev`      |
| Arch             | `pacman -S highs`                   |
| NixOS            | `nix-env -iA nixpkgs.highs`         |
| From source      | [github.com/ERGO-Code/HiGHS](https://github.com/ERGO-Code/HiGHS) |

The build discovers HiGHS through `pkg-config`. If your install is in
a non-standard location:

```sh
export HIGHS_CFLAGS="-I/path/to/include"
export HIGHS_LIBS="-L/path/to/lib -lhighs"
```

## Building models

### Variables

```ocaml
Var.create ()                                          (* continuous, [0, +inf], cost 0 *)
Var.continuous ~name:"x" ~lower:0. ~upper:10. ~cost:1. ()
Var.integer    ~name:"n" ~lower:0. ~upper:100. ()
Var.binary     ~name:"b" ~cost:5. ()                   (* implicit bounds [0, 1] *)
```

`Var_kind.t` values: `Continuous | Integer | Binary | Semi_continuous
| Semi_integer`.

### Constraints

Each constraint has a list of `Term.t = float * int` and lower / upper
bounds:

```ocaml
Constraint.eq    ~terms:[(1., 0); (1., 1)] ~rhs:5. ()
Constraint.leq   ~terms:[(1., 0); (2., 1)] ~rhs:10. ()
Constraint.geq   ~terms:[(3., 0)] ~rhs:2. ()
Constraint.range ~terms:[(1., 0); (1., 1)] ~lower:1. ~upper:4. ()
```

Read `(4., 0)` as "4 times variable 0". The list order is irrelevant.

### Models

```ocaml
Model.create
  ~name:"my_lp"
  ~sense:Minimize    (* or Maximize *)
  ~offset:0.         (* constant added to the objective *)
  ~vars:[| ... |]
  ~constraints:[| ... |]
  ()
```

### Options

```ocaml
let opts =
  { Options.default with
    time_limit = Some 60.
  ; mip_gap    = Some 1e-4
  ; output     = false
  ; solver     = Simplex
  ; extra      = [("random_seed", Int 42)]
  }
```

`Options.default` gives sensible defaults: no time limit, HiGHS's
default gap, `output = false`, all other typed knobs on `Auto`.
Anything HiGHS understands but we don't have a typed field for goes
in `extra`, with values of `Option_value.t = Bool _ | Int _ | Float
_ | String _`.

Unknown option names surface in `Solver_error` with the offending key
included.

### Solving

```ocaml
match solve m ~options:opts with
| Ok sol ->
  (match sol.status with
   | Optimal -> printf "obj = %f\n" sol.objective
   | Infeasible -> printf "no feasible point\n"
   | s -> print_s [%sexp (s : Status.t)])
| Error e -> print_s [%sexp (e : Error.t)]
```

Or when you'd rather have exceptions:

```ocaml
let sol = solve_exn m ~options:opts in
match sol.status with
| Optimal -> ...
```

`Solution.t` is a record with primal + dual values per variable and per
constraint, plus `simplex_iterations` and `mip_nodes` counters:

```ocaml
{ status             : Status.t
; objective          : float
; values             : float array
; duals              : float array
; row_values         : float array
; row_duals          : float array
; simplex_iterations : Int64.t
; mip_nodes          : Int64.t
}
```

## Sexp-based diagnostics

Every public record derives `sexp_of`, so a model or solution prints
cleanly with `print_s [%sexp (m : Model.t)]`:

```ocaml
# print_s [%sexp (Options.default : Options.t)];;
((time_limit ()) (mip_gap ()) (threads ()) (output false) (solver Auto)
 (presolve Auto) (parallel Auto) (extra ()))
```

## Examples

- [`examples/lp.ml`](examples/lp.ml) — 3-food diet LP, optimum 1.7917.
- [`examples/knapsack.ml`](examples/knapsack.ml) — 10-item 0/1 knapsack
  MIP, optimum 309. Same instance as the ocaml-hexaly knapsack.

Run:
```sh
dune exec examples/lp.exe
dune exec examples/knapsack.exe
```

## Testing

Inline expect tests in `test/test_highs.ml`, driven by
`ppx_expect`. Run with `dune runtest`. When you change output, dune
prints a diff you can accept with `dune promote`.

## Comparison to ocaml-hexaly

Same author, different solver.

|                              | ocaml-highs                | ocaml-hexaly              |
| ---------------------------- | -------------------------- | ------------------------- |
| Solver license               | MIT (open source)          | Proprietary               |
| Problem classes              | LP, MIP (QP soon)          | LP, MIP, CP, scheduling, routing |
| Decision variable kinds      | bool, int, float           | + interval, list, set     |
| Binding depth                | 3 layers (no C++ shim)     | 4 layers (C++ shim)       |
| Model representation         | Immutable record + `solve` | Mutable builder + `solve` |
| CI                           | Public runners work        | Needs a licensed CI       |
| Style                        | Jane Street (Base + ppx_jane) | Stdlib-only            |

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT for this binding. HiGHS is also MIT.
