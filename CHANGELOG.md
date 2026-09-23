# Changelog

## [0.1.0] - 2026-09-24

First release. Jane Street-style bindings to HiGHS 1.11+ (tested against 1.11
and 1.15).

### Added

- Module per type: `Sense`, `Var_kind`, `Var`, `Term`, `Constraint`, `Model`,
  `Solver_algorithm`, `Toggle`, `Option_value`, `Options`, `Status`,
  `Solution`, `Version`.
- Every record type derives `sexp_of`, `compare`, `equal` (and `fields`
  where useful) via `ppx_jane`.
- `solve : ?options:Options.t -> Model.t -> Solution.t Or_error.t` with
  `solve_exn` companion.
- `write : ?options:Options.t -> Model.t -> string -> unit Or_error.t`
  with `write_exn` companion.
- `Solver_error of string` exception with the offending option name or
  file path in the message.
- Typed common options plus `extra : (string * Option_value.t) list`
  escape hatch for any HiGHS option keyed by name.
- Inline `ppx_expect` tests covering version, model construction (pure
  records), LP minimize/maximize, solution shape, infeasible / unbounded
  outcomes, MIP knapsack (optimum 309), option handling (including
  unknown-key error surfacing), `Or_error` interface, MPS write, and
  a 200-solve GC stress loop.
- Two worked examples: diet LP (optimum 1.7917), 10-item knapsack MIP.
- Portable build via `dune-configurator` + `pkg-config`, with
  `HIGHS_CFLAGS` / `HIGHS_LIBS` overrides.
- opam depexts for homebrew, Debian, Arch, NixOS.

### Dependencies

- Runtime: `base`, `ppx_jane`.
- Test-only: `core`, `expect_test_helpers_core`.
- Build-only: `dune-configurator`.

### Known limitations

- No quadratic programming (`Highs_passHessian` family).
- No callbacks.
- No `read : string -> Model.t` (reading MPS/LP into a pure model).
  `write` works because it is a straight-through call.
- No cutpool, basis I/O, or presolve/postsolve pipeline exposure.
