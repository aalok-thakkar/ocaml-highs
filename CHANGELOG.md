# Changelog

## [0.1.0] - 2026-09-23

First release. Functional binding to HiGHS 1.15 (also tested on 1.11).

### Added

- Pure model type built from immutable records: `var`, `term`,
  `constr`, `model`, and pure constructors (`continuous`, `integer`,
  `binary`, `eq`, `leq`, `geq`, `range`, `model`).
- `solve : ?options:options -> model -> solution` as the sole
  side-effecting entry point.
- `options` record with typed fields for `time_limit`, `mip_gap`,
  `threads`, `output`, `solver`, `presolve`, `parallel`, plus an
  `extra : (string * option_value) list` escape hatch for any HiGHS
  option keyed by name.
- `status` variant covering the useful `HighsModelStatus` values
  (`Optimal`, `Infeasible`, `Unbounded`, `Unbounded_or_infeasible`,
  `Time_limit`, `Iteration_limit`, `Model_error`, `Interrupted`,
  `Not_solved`), with `Other of string` for the rare ones.
- Solution record with primal + dual values per variable and per
  constraint, plus `simplex_iterations` and `mip_nodes` counters.
- `Solver_error of string` with the offending option name or file
  path included in the message.
- `write : model -> string -> unit` for MPS / LP file export.
- `Version` module.
- Portable build via `dune-configurator` + `pkg-config`, with
  `HIGHS_CFLAGS` / `HIGHS_LIBS` environment overrides.
- opam depexts for homebrew (`highs`), Debian (`libhighs-dev`), Arch
  (`highs`), and NixOS (`highs`).
- 19 alcotest cases across version, constructors, LP, MIP, status
  outcomes, options (including extras escape hatch and unknown-key
  error surfacing), file I/O, and a 200-solve GC stress loop.
- Two worked examples: diet LP (optimum 1.7917), 10-item knapsack
  MIP (optimum 309).

### Known limitations

- No quadratic programming (`Highs_passHessian` family).
- No callbacks.
- No `read : string -> model` (reading MPS/LP into a pure model).
  `write` works because it is a straight-through call.
- No cutpool, basis I/O, or presolve/postsolve pipeline exposure.
- Tested on HiGHS 1.11 and 1.15; other versions are likely fine given
  HiGHS's stable C API but untested here.
