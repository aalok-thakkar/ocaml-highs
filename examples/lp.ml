(* The classic diet problem: three foods, two nutrient constraints.
 *
 *   minimize   0.5 bread + 0.3 milk + 0.7 meat
 *   subject to
 *     protein:  4 bread +  8 milk + 20 meat >= 50
 *     calcium:  2 bread + 12 milk +  3 meat >= 30
 *     bread, milk, meat >= 0
 *
 * Run: dune exec examples/lp.exe *)

open Base
open Stdio
open Highs

let () =
  let m =
    Model.create
      ~name:"diet"
      ~sense:Minimize
      ~vars:[|
        Var.continuous ~name:"bread" ~cost:0.5 ();
        Var.continuous ~name:"milk"  ~cost:0.3 ();
        Var.continuous ~name:"meat"  ~cost:0.7 ();
      |]
      ~constraints:[|
        Constraint.geq ~name:"protein" ~rhs:50.
          ~terms:[(4., 0); (8., 1); (20., 2)] ();
        Constraint.geq ~name:"calcium" ~rhs:30.
          ~terms:[(2., 0); (12., 1); (3., 2)] ();
      |]
      ()
  in
  match solve m with
  | Error e ->
    Stdio.eprintf "solve failed: %s\n" (Error.to_string_hum e);
    Stdlib.exit 1
  | Ok sol ->
    match sol.status with
    | Optimal ->
      printf "status : %s\n" (Status.to_string sol.status);
      printf "cost   : %.4f\n" sol.objective;
      printf "diet   : bread=%.3f  milk=%.3f  meat=%.3f\n"
        sol.values.(0) sol.values.(1) sol.values.(2);
      printf "duals  : protein=%.3f  calcium=%.3f\n"
        sol.row_duals.(0) sol.row_duals.(1)
    | s ->
      Stdio.eprintf "no optimum: %s\n" (Status.to_string s);
      Stdlib.exit 1
