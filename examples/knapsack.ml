(* 0/1 knapsack as a MIP. Same instance as the ocaml-hexaly knapsack.
 * Optimum: value 309, weight 165.
 *
 * Run: dune exec examples/knapsack.exe *)

open Base
open Stdio
open Highs

let weights  = [| 23; 31; 29; 44; 53; 38; 63; 85; 89; 82 |]
let values   = [| 92; 57; 49; 68; 60; 43; 67; 84; 87; 72 |]
let capacity = 165

let () =
  let n = Array.length weights in
  let vars =
    Array.init n ~f:(fun i ->
      Var.binary
        ~name:(Printf.sprintf "x%d" i)
        ~cost:(Float.of_int values.(i))
        ())
  in
  let weight_terms =
    List.init n ~f:(fun i -> (Float.of_int weights.(i), i))
  in
  let m =
    Model.create
      ~name:"knapsack"
      ~sense:Maximize
      ~vars
      ~constraints:[|
        Constraint.leq ~name:"capacity"
          ~terms:weight_terms
          ~rhs:(Float.of_int capacity) ();
      |]
      ()
  in
  let options = { Options.default with output = false; mip_gap = Some 0. } in
  let sol = solve_exn m ~options in
  printf "status : %s\n" (Status.to_string sol.status);
  printf "value  : %.0f\n" sol.objective;
  let total_w = ref 0 in
  Array.iteri sol.values ~f:(fun i x ->
    if Float.(x > 0.5) then total_w := !total_w + weights.(i));
  printf "weight : %d / %d\n" !total_w capacity;
  printf "picked :";
  Array.iteri sol.values ~f:(fun i x ->
    if Float.(x > 0.5) then printf " %d" i);
  print_endline "";
  printf "nodes  : %Ld\n" sol.mip_nodes
