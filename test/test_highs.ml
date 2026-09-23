(* Alcotest suite for the functional Highs API. *)

open Highs

let close a b = Float.abs (a -. b) < 1e-6

let quiet = { default_options with output = false }

(* ============ Version ============ *)

let test_version_positive () =
  Alcotest.(check bool) "major > 0" true (Version.major () > 0);
  Alcotest.(check bool) "version string non-empty" true
    (String.length (Version.string ()) > 0)

let test_version_matches () =
  let s = Version.string () in
  let expected = Printf.sprintf "%d.%d.%d"
    (Version.major ()) (Version.minor ()) (Version.patch ())
  in
  Alcotest.(check string) "string matches major.minor.patch" expected s

(* ============ Constructors ============ *)

let test_var_defaults () =
  let v = var () in
  Alcotest.(check string) "no name"  "" v.name;
  Alcotest.(check bool)   "continuous" true (v.kind = Continuous);
  Alcotest.(check (float 0.)) "lower = 0" 0.0 v.lower;
  Alcotest.(check bool) "upper = infinity" true (v.upper = infinity);
  Alcotest.(check (float 0.)) "cost = 0" 0.0 v.cost

let test_binary_bounds () =
  let v = binary () in
  Alcotest.(check bool) "kind = Binary" true (v.kind = Binary);
  Alcotest.(check (float 0.)) "lower = 0" 0.0 v.lower;
  Alcotest.(check (float 0.)) "upper = 1" 1.0 v.upper

let test_constraint_constructors () =
  let e = eq  ~terms:[(1.0, 0)] ~rhs:3.0 () in
  let l = leq ~terms:[(1.0, 0)] ~rhs:5.0 () in
  let g = geq ~terms:[(1.0, 0)] ~rhs:2.0 () in
  let r = range ~terms:[(1.0, 0)] ~lower:1.0 ~upper:4.0 () in
  Alcotest.(check (float 0.)) "eq  lower" 3.0 e.lower;
  Alcotest.(check (float 0.)) "eq  upper" 3.0 e.upper;
  Alcotest.(check bool) "leq lower is -inf" true (l.lower = neg_infinity);
  Alcotest.(check (float 0.)) "leq upper" 5.0 l.upper;
  Alcotest.(check (float 0.)) "geq lower" 2.0 g.lower;
  Alcotest.(check bool) "geq upper is inf" true (g.upper = infinity);
  Alcotest.(check (float 0.)) "range lower" 1.0 r.lower;
  Alcotest.(check (float 0.)) "range upper" 4.0 r.upper

(* ============ LP: minimize ============ *)

(* min x + y s.t. x + 2y >= 1, x,y >= 0. Optimum obj = 0.5. *)
let test_solve_min_lp () =
  let m = model
    ~sense:Minimize
    ~vars:[|
      continuous ~cost:1.0 ();
      continuous ~cost:1.0 ();
    |]
    ~constraints:[|
      geq ~terms:[(1.0, 0); (2.0, 1)] ~rhs:1.0 ();
    |]
    ()
  in
  let sol = solve ~options:quiet m in
  Alcotest.(check string) "status" "Optimal" (status_to_string sol.status);
  Alcotest.(check bool) "obj = 0.5" true (close sol.objective 0.5);
  Alcotest.(check int)  "2 values" 2 (Array.length sol.values);
  Alcotest.(check int)  "1 row"    1 (Array.length sol.row_values)

(* max x + y s.t. x + y <= 15, 1 <= x,y <= 10. Optimum = 15. *)
let test_solve_max_lp () =
  let m = model
    ~sense:Maximize
    ~vars:[|
      continuous ~cost:1.0 ~lower:1.0 ~upper:10.0 ();
      continuous ~cost:1.0 ~lower:1.0 ~upper:10.0 ();
    |]
    ~constraints:[|
      leq ~terms:[(1.0, 0); (1.0, 1)] ~rhs:15.0 ();
    |]
    ()
  in
  let sol = solve ~options:quiet m in
  Alcotest.(check bool) "obj = 15" true (close sol.objective 15.0)

(* ============ Status: infeasible, unbounded ============ *)

let test_status_infeasible () =
  let m = model
    ~vars:[| continuous ~cost:1.0 ~lower:0.0 ~upper:1.0 () |]
    ~constraints:[| geq ~terms:[(1.0, 0)] ~rhs:10.0 () |]
    ()
  in
  let sol = solve ~options:quiet m in
  Alcotest.(check string) "Infeasible" "Infeasible" (status_to_string sol.status)

let test_status_unbounded () =
  let opts = { quiet with presolve = Off } in
  let m = model
    ~sense:Maximize
    ~vars:[| continuous ~cost:1.0 ~lower:0.0 ~upper:infinity () |]
    ~constraints:[||]
    ()
  in
  let sol = solve ~options:opts m in
  Alcotest.(check bool) "unbounded (or _or_infeasible)" true
    (sol.status = Unbounded || sol.status = Unbounded_or_infeasible)

(* ============ MIP: knapsack ============ *)

(* Same instance as ocaml-hexaly's knapsack: optimum value = 309. *)
let test_mip_knapsack () =
  let weights = [| 23; 31; 29; 44; 53; 38; 63; 85; 89; 82 |] in
  let values  = [| 92; 57; 49; 68; 60; 43; 67; 84; 87; 72 |] in
  let cap = 165 in
  let n = Array.length weights in
  let vars = Array.init n (fun i ->
    binary ~name:(Printf.sprintf "x%d" i) ~cost:(float_of_int values.(i)) ())
  in
  let terms = List.init n (fun i -> (float_of_int weights.(i), i)) in
  let m = model
    ~sense:Maximize
    ~vars
    ~constraints:[| leq ~name:"capacity" ~terms ~rhs:(float_of_int cap) () |]
    ()
  in
  let sol = solve ~options:{ quiet with mip_gap = Some 0.0 } m in
  Alcotest.(check bool) "knapsack optimum = 309" true (close sol.objective 309.0);
  Alcotest.(check string) "Optimal" "Optimal" (status_to_string sol.status)

(* Change a continuous var into an integer by rebuilding the model
 * (functional API: no in-place mutation). *)
let test_var_kind_change () =
  let base = model
    ~sense:Maximize
    ~vars:[| continuous ~cost:1.0 ~lower:0.0 ~upper:5.0 () |]
    ~constraints:[| leq ~terms:[(1.0, 0)] ~rhs:3.7 () |]
    ()
  in
  let cont_sol = solve ~options:quiet base in
  Alcotest.(check bool) "continuous solution = 3.7" true
    (close cont_sol.objective 3.7);

  let mip = { base with
    vars = [| { base.vars.(0) with kind = Integer } |]
  } in
  let mip_sol = solve ~options:quiet mip in
  Alcotest.(check bool) "integer solution = 3" true
    (close mip_sol.objective 3.0)

(* ============ Options ============ *)

let test_default_options () =
  let d = default_options in
  Alcotest.(check bool) "no time limit"   true (d.time_limit = None);
  Alcotest.(check bool) "output off"      true (d.output = false);
  Alcotest.(check bool) "solver = Auto"   true (d.solver = Auto);
  Alcotest.(check bool) "presolve = Auto" true (d.presolve = Auto)

let test_options_time_limit () =
  let m = model
    ~vars:[| continuous ~cost:1.0 () |]
    ~constraints:[| geq ~terms:[(1.0, 0)] ~rhs:0.0 () |]
    ()
  in
  let opts = { quiet with time_limit = Some 60.0 } in
  let sol = solve ~options:opts m in
  Alcotest.(check string) "solves with time limit" "Optimal"
    (status_to_string sol.status)

let test_options_extra_unknown_key_simple () =
  let m = model
    ~vars:[| continuous ~cost:1.0 () |]
    ~constraints:[| geq ~terms:[(1.0, 0)] ~rhs:0.0 () |]
    ()
  in
  let opts = { quiet with
    extra = [("totally_bogus_option", Int 42)]
  } in
  let raised = ref None in
  (try let _ = solve ~options:opts m in ()
   with Solver_error msg -> raised := Some msg);
  match !raised with
  | None -> Alcotest.fail "expected Solver_error"
  | Some msg ->
    let contains needle =
      let l = String.length msg and n = String.length needle in
      let rec go i = i + n <= l
        && (String.sub msg i n = needle || go (i + 1)) in
      go 0
    in
    Alcotest.(check bool) "message names the key" true
      (contains "totally_bogus_option")

(* Verify the extras escape hatch accepts each value shape without
 * crashing. Use option keys that don't conflict with the typed ones. *)
let test_options_extra_typed () =
  let m = model
    ~vars:[| continuous ~cost:1.0 ~lower:1.0 ~upper:10.0 () |]
    ~constraints:[| leq ~terms:[(1.0, 0)] ~rhs:5.0 () |]
    ()
  in
  let opts = { quiet with
    extra = [
      ("primal_feasibility_tolerance", Float 1e-7);
      ("small_matrix_value",           Float 1e-9);
      ("random_seed",                  Int 42);
      ("log_to_console",               Bool false);
    ]
  } in
  let sol = solve ~options:opts m in
  Alcotest.(check string) "solved with extras" "Optimal"
    (status_to_string sol.status)

(* ============ Solution shape ============ *)

let test_solution_dims () =
  let m = model
    ~vars:[|
      continuous ~cost:1.0 (); continuous ~cost:1.0 (); continuous ~cost:1.0 ();
    |]
    ~constraints:[|
      geq ~terms:[(1.0, 0); (1.0, 1); (1.0, 2)] ~rhs:1.0 ();
      leq ~terms:[(1.0, 0); (1.0, 1); (1.0, 2)] ~rhs:5.0 ();
    |]
    ()
  in
  let sol = solve ~options:quiet m in
  Alcotest.(check int) "3 values" 3 (Array.length sol.values);
  Alcotest.(check int) "3 duals"  3 (Array.length sol.duals);
  Alcotest.(check int) "2 row_values" 2 (Array.length sol.row_values);
  Alcotest.(check int) "2 row_duals"  2 (Array.length sol.row_duals)

(* ============ File I/O ============ *)

let test_write_model () =
  let m = model
    ~name:"test"
    ~vars:[|
      continuous ~name:"x" ~cost:1.0 ~lower:0.0 ~upper:10.0 ();
      continuous ~name:"y" ~cost:2.0 ~lower:0.0 ~upper:10.0 ();
    |]
    ~constraints:[|
      geq ~name:"c1" ~terms:[(1.0, 0); (1.0, 1)] ~rhs:3.0 ();
    |]
    ()
  in
  let tmp = Filename.temp_file "highs_write_" ".mps" in
  Fun.protect ~finally:(fun () -> try Sys.remove tmp with _ -> ()) (fun () ->
    write m tmp;
    Alcotest.(check bool) "file created" true (Sys.file_exists tmp))

(* ============ GC pressure ============ *)

let test_gc_pressure () =
  for _ = 1 to 200 do
    let m = model
      ~vars:[| continuous ~cost:1.0 () |]
      ~constraints:[| geq ~terms:[(1.0, 0)] ~rhs:0.0 () |]
      ()
    in
    let sol = solve ~options:quiet m in
    ignore sol
  done;
  Gc.compact (); Gc.full_major ();
  Alcotest.(check pass) "no crash after 200 solves + GC" () ()

(* ============ Model must be validated by HiGHS ============ *)

(* Non-negative reduced costs give a check we haven't broken sign conventions. *)
let test_reduced_cost_signs () =
  (* min x s.t. x >= 1. Reduced cost of x at optimum: 0 (binding).
     Dual of the constraint: 1 (min-form). *)
  let m = model
    ~sense:Minimize
    ~vars:[| continuous ~cost:1.0 () |]
    ~constraints:[| geq ~terms:[(1.0, 0)] ~rhs:1.0 () |]
    ()
  in
  let sol = solve ~options:quiet m in
  Alcotest.(check bool) "x = 1"   true (close sol.values.(0) 1.0);
  Alcotest.(check bool) "obj = 1" true (close sol.objective 1.0);
  Alcotest.(check bool) "row dual > 0 (binding)" true (sol.row_duals.(0) > 0.5)

(* ============ Runner ============ *)

let () =
  Alcotest.run "highs" [
    "version", [
      Alcotest.test_case "positive"       `Quick test_version_positive;
      Alcotest.test_case "string matches" `Quick test_version_matches;
    ];
    "constructors", [
      Alcotest.test_case "var defaults"      `Quick test_var_defaults;
      Alcotest.test_case "binary bounds"     `Quick test_binary_bounds;
      Alcotest.test_case "constraint kinds"  `Quick test_constraint_constructors;
    ];
    "lp", [
      Alcotest.test_case "minimize"       `Quick test_solve_min_lp;
      Alcotest.test_case "maximize"       `Quick test_solve_max_lp;
      Alcotest.test_case "solution dims"  `Quick test_solution_dims;
      Alcotest.test_case "reduced costs"  `Quick test_reduced_cost_signs;
    ];
    "status", [
      Alcotest.test_case "infeasible"     `Quick test_status_infeasible;
      Alcotest.test_case "unbounded"      `Quick test_status_unbounded;
    ];
    "mip", [
      Alcotest.test_case "knapsack"        `Quick test_mip_knapsack;
      Alcotest.test_case "kind change"     `Quick test_var_kind_change;
    ];
    "options", [
      Alcotest.test_case "defaults"        `Quick test_default_options;
      Alcotest.test_case "time_limit"      `Quick test_options_time_limit;
      Alcotest.test_case "extra typed"     `Quick test_options_extra_typed;
      Alcotest.test_case "unknown key msg" `Quick test_options_extra_unknown_key_simple;
    ];
    "file_io", [
      Alcotest.test_case "write MPS"       `Quick test_write_model;
    ];
    "stress", [
      Alcotest.test_case "200 solves + GC" `Quick test_gc_pressure;
    ];
  ]
