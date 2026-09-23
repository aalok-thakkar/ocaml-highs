# highs

[![opam](https://img.shields.io/badge/opam-highs-blue)](https://opam.ocaml.org/packages/highs/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

OCaml bindings for **[HiGHS](https://highs.dev)**, the open-source
linear, mixed-integer, and quadratic programming solver from the
University of Edinburgh.

The interface is functional: you describe an optimization problem as an
immutable OCaml record, hand it to `Highs.solve`, and get back a fresh
solution record. No handles, no builders, no in-place mutation on the
user side.

```ocaml
open Highs

let m = model
  ~sense:Minimize
  ~vars:[|
    continuous ~name:"bread" ~cost:0.5 ();
    continuous ~name:"milk"  ~cost:0.3 ();
    continuous ~name:"meat"  ~cost:0.7 ();
  |]
  ~constraints:[|
    geq ~name:"protein" ~terms:[(4.0, 0); (8.0, 1); (20.0, 2)] ~rhs:50.0 ();
    geq ~name:"calcium" ~terms:[(2.0, 0); (12.0, 1); (3.0, 2)] ~rhs:30.0 ();
  |]
  ()

let () =
  let sol = solve m in
  match sol.status with
  | Optimal ->
    Printf.printf "cost = %.4f\n" sol.objective;
    Array.iteri (Printf.printf "  x[%d] = %f\n") sol.values
  | s -> Printf.printf "no optimum: %s\n" (status_to_string s)
```

## Design in one paragraph

Everything the user builds is a pure record: `var`, `term`, `constr`,
`model`, `options`. `solve : ?options:options -> model -> solution` is
the only function that touches HiGHS. It creates a handle, applies
options, encodes the model into HiGHS's arrays, runs the solver,
extracts the solution, releases the handle, and returns. If you like,
think of it as an interpreter: `model` is the AST, `solve` is
`eval`, and `solution` is the result.

## Status

Version 0.1.0. Tested against HiGHS 1.15.1 on macOS Apple Silicon,
OCaml 5.1.

19 alcotest cases across version, constructors, LP, MIP, status,
options (including the extras escape hatch), file I/O, and a 200-solve
GC stress loop. Two worked examples: a diet LP and a 10-item knapsack
MIP. `opam install .` and `opam install . --with-test` both succeed;
`opam lint` passes with depexts declared.

Deferred to 0.2+: quadratic programming, callbacks, cutpool exposure,
basis I/O, `read : string -> model` (model export from a HiGHS handle
back to an OCaml record).

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

The build discovers HiGHS through pkg-config. If your install is in a
non-standard location, set:

```sh
export HIGHS_CFLAGS="-I/path/to/include"
export HIGHS_LIBS="-L/path/to/lib -lhighs"
```

## Full API tour

### Variables

```ocaml
val var        : ?name:string -> ?kind:var_kind -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> var
val continuous : ?name:string -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> var
val integer    : ?name:string -> ?lower:int   -> ?upper:int   -> ?cost:float -> unit -> var
val binary     : ?name:string -> ?cost:float  -> unit -> var
```

`var_kind` is `Continuous | Integer | Binary | Semi_continuous |
Semi_integer`. `binary ()` is a shortcut for an integer variable with
bounds `[0, 1]`.

### Constraints

Each constraint is a list of `(coefficient, variable_index)` terms
plus a bound.

```ocaml
val eq    : ?name:string -> terms:term list -> rhs:float -> unit -> constr
val leq   : ?name:string -> terms:term list -> rhs:float -> unit -> constr
val geq   : ?name:string -> terms:term list -> rhs:float -> unit -> constr
val range : ?name:string -> terms:term list -> lower:float -> upper:float -> unit -> constr
```

`term` is a pair `float * int`: coefficient first, then variable index.

### Model

```ocaml
val model :
  ?name:string ->
  ?sense:sense ->                    (* Minimize | Maximize, default Minimize *)
  ?offset:float ->                   (* constant added to the objective *)
  vars:var array ->
  constraints:constr array ->
  unit -> model
```

### Options

```ocaml
type options = {
  time_limit : float option;         (* seconds *)
  mip_gap    : float option;         (* relative MIP gap tolerance *)
  threads    : int option;
  output     : bool;                 (* HiGHS's own log *)
  solver     : solver;               (* Simplex | Ipm | Pdlp | Auto *)
  presolve   : toggle;               (* On | Off | Auto *)
  parallel   : toggle;
  extra      : (string * option_value) list;  (* any HiGHS option by name *)
}
```

Common usage:
```ocaml
let opts = { default_options with
  time_limit = Some 60.0;
  mip_gap    = Some 1e-4;
  output     = true;
}
```

Anything HiGHS understands but we don't have a typed field for goes in
`extra`, with `Bool _ | Int _ | Float _ | String _`:
```ocaml
let opts = { default_options with
  extra = [
    ("random_seed",                  Int 42);
    ("primal_feasibility_tolerance", Float 1e-7);
  ]
}
```

Unknown option names raise `Solver_error` with the offending key in
the message.

### Solve

```ocaml
val solve : ?options:options -> model -> solution

type solution = {
  status : status;
  objective : float;
  values : float array;
  duals : float array;
  row_values : float array;
  row_duals : float array;
  simplex_iterations : int64;
  mip_nodes : int64;
}
```

`status` covers `Optimal | Infeasible | Unbounded |
Unbounded_or_infeasible | Time_limit | Iteration_limit | Model_error |
Interrupted | Not_solved | Other of string`.

### Errors

`exception Solver_error of string`. Raised on internal HiGHS errors
(bad option key, malformed model, unwritable file). Infeasible and
unbounded models are NOT errors; they are outcomes reported through
`status`.

## Examples

- [`examples/lp.ml`](examples/lp.ml) — 3-food diet LP, optimum 1.7917.
- [`examples/knapsack.ml`](examples/knapsack.ml) — 10-item 0/1 knapsack
  MIP, optimum 309. Same instance as the ocaml-hexaly knapsack.

Run:
```sh
dune exec examples/lp.exe
dune exec examples/knapsack.exe
```

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

Pick highs for classical LP/MIP. Pick hexaly if you need scheduling,
routing, or the combinatorial variable types.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the extension recipe.
Adding a new HiGHS entry point is three edits since there's no C++
shim in between.

## License

MIT for this binding. HiGHS is also MIT.
