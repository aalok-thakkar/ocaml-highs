(* The classic diet problem: three foods, two nutrient constraints.
 *
 *   minimize   0.5 bread + 0.3 milk + 0.7 meat
 *   subject to
 *     protein:  4 bread +  8 milk + 20 meat >= 50
 *     calcium:  2 bread + 12 milk +  3 meat >= 30
 *     bread, milk, meat >= 0
 *
 * Run: dune exec examples/lp.exe *)

open Highs

let () =
  let m = model
    ~name:"diet"
    ~sense:Minimize
    ~vars:[|
      continuous ~name:"bread" ~cost:0.5 ();
      continuous ~name:"milk"  ~cost:0.3 ();
      continuous ~name:"meat"  ~cost:0.7 ();
    |]
    ~constraints:[|
      geq ~name:"protein" ~rhs:50.0
        ~terms:[(4.0, 0); (8.0, 1); (20.0, 2)] ();
      geq ~name:"calcium" ~rhs:30.0
        ~terms:[(2.0, 0); (12.0, 1); (3.0, 2)] ();
    |]
    ()
  in
  let sol = solve m in
  match sol.status with
  | Optimal ->
    Printf.printf "status : %s\n" (status_to_string sol.status);
    Printf.printf "cost   : %.4f\n" sol.objective;
    Printf.printf "diet   : bread=%.3f  milk=%.3f  meat=%.3f\n"
      sol.values.(0) sol.values.(1) sol.values.(2);
    Printf.printf "duals  : protein=%.3f  calcium=%.3f\n"
      sol.row_duals.(0) sol.row_duals.(1)
  | s ->
    Printf.eprintf "no optimum: %s\n" (status_to_string s);
    exit 1
