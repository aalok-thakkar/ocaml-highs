(* 0/1 knapsack as a MIP.
 *
 * Same instance as the ocaml-hexaly knapsack example so the two
 * bindings solve the same problem for cross-comparison.
 *
 * Optimum: value 309, weight 165.
 *
 * Run: dune exec examples/knapsack.exe *)

open Highs

let weights  = [| 23; 31; 29; 44; 53; 38; 63; 85; 89; 82 |]
let values   = [| 92; 57; 49; 68; 60; 43; 67; 84; 87; 72 |]
let capacity = 165

let () =
  let n = Array.length weights in
  let vars = Array.init n (fun i ->
    binary
      ~name:(Printf.sprintf "x%d" i)
      ~cost:(float_of_int values.(i))
      ())
  in
  let weight_terms =
    List.init n (fun i -> (float_of_int weights.(i), i))
  in
  let m = model
    ~name:"knapsack"
    ~sense:Maximize
    ~vars
    ~constraints:[|
      leq ~name:"capacity" ~terms:weight_terms ~rhs:(float_of_int capacity) ();
    |]
    ()
  in
  let opts = { default_options with mip_gap = Some 0.0 } in
  let sol = solve ~options:opts m in
  Printf.printf "status : %s\n" (status_to_string sol.status);
  Printf.printf "value  : %.0f\n" sol.objective;
  let total_w = ref 0 in
  Array.iteri (fun i x ->
    if x > 0.5 then total_w := !total_w + weights.(i)) sol.values;
  Printf.printf "weight : %d / %d\n" !total_w capacity;
  Printf.printf "picked :";
  Array.iteri (fun i x -> if x > 0.5 then Printf.printf " %d" i) sol.values;
  print_newline ();
  Printf.printf "nodes  : %Ld\n" sol.mip_nodes
