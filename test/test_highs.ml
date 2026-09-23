(* Synchronous Expect_test_config that satisfies the ppx_expect signature.
   Placed before [open Core] so its types are Stdlib.unit / Stdlib.string. *)
module Expect_test_config
  : Expect_test_config_types.S with type 'a IO.t = 'a
= struct
  module IO = struct
    type 'a t = 'a
    let return x = x
  end
  let run f = f ()
  let sanitize s = s
  let upon_unreleasable_issue = `CR
end

open! Core
open Highs

let quiet = { Options.default with output = false }

(* -- Version -- *)

let%expect_test "version is a sensible triple" =
  printf "major_positive=%b minor_nonneg=%b patch_nonneg=%b\n"
    (Version.major () > 0)
    (Version.minor () >= 0)
    (Version.patch () >= 0);
  [%expect {| major_positive=true minor_nonneg=true patch_nonneg=true |}]

(* -- Model construction (pure) -- *)

let%expect_test "var defaults" =
  let v = Var.create () in
  print_s [%sexp (v : Var.t)];
  [%expect {| ((name "") (kind Continuous) (lower 0) (upper INF) (cost 0)) |}]

let%expect_test "binary fixes bounds" =
  let v = Var.binary ~name:"x" ~cost:2. () in
  print_s [%sexp (v : Var.t)];
  [%expect {| ((name x) (kind Binary) (lower 0) (upper 1) (cost 2)) |}]

let%expect_test "constraint constructors" =
  let show c = print_s [%sexp (c : Constraint.t)] in
  show (Constraint.eq  ~terms:[(1., 0)] ~rhs:3.  ());
  show (Constraint.leq ~terms:[(1., 0)] ~rhs:5.  ());
  show (Constraint.geq ~terms:[(1., 0)] ~rhs:2.  ());
  show (Constraint.range ~terms:[(1., 0)] ~lower:1. ~upper:4. ());
  [%expect {|
    ((name "") (lower 3) (upper 3) (terms ((1 0))))
    ((name "") (lower -INF) (upper 5) (terms ((1 0))))
    ((name "") (lower 2) (upper INF) (terms ((1 0))))
    ((name "") (lower 1) (upper 4) (terms ((1 0)))) |}]

(* -- LP -- *)

let%expect_test "minimize x + y s.t. x + 2y >= 1" =
  let m = Model.create
    ~sense:Minimize
    ~vars:[| Var.continuous ~cost:1. (); Var.continuous ~cost:1. () |]
    ~constraints:[| Constraint.geq ~terms:[(1., 0); (2., 1)] ~rhs:1. () |]
    ()
  in
  let sol = solve_exn m ~options:quiet in
  printf "%s obj=%.4f\n" (Status.to_string sol.status) sol.objective;
  [%expect {| Optimal obj=0.5000 |}]

let%expect_test "maximize x + y s.t. x + y <= 15, 1 <= vars <= 10" =
  let m = Model.create
    ~sense:Maximize
    ~vars:[|
      Var.continuous ~cost:1. ~lower:1. ~upper:10. ();
      Var.continuous ~cost:1. ~lower:1. ~upper:10. ();
    |]
    ~constraints:[| Constraint.leq ~terms:[(1., 0); (1., 1)] ~rhs:15. () |]
    ()
  in
  let sol = solve_exn m ~options:quiet in
  printf "%s obj=%.4f\n" (Status.to_string sol.status) sol.objective;
  [%expect {| Optimal obj=15.0000 |}]

let%expect_test "solution has one dual per var and per row" =
  let m = Model.create
    ~vars:[| Var.continuous ~cost:1. (); Var.continuous ~cost:1. () |]
    ~constraints:[|
      Constraint.geq ~terms:[(1., 0); (1., 1)] ~rhs:1. ();
      Constraint.leq ~terms:[(1., 0); (1., 1)] ~rhs:5. ();
    |]
    ()
  in
  let sol = solve_exn m ~options:quiet in
  printf "cols=%d col_duals=%d rows=%d row_duals=%d\n"
    (Array.length sol.values) (Array.length sol.duals)
    (Array.length sol.row_values) (Array.length sol.row_duals);
  [%expect {| cols=2 col_duals=2 rows=2 row_duals=2 |}]

(* -- Status outcomes -- *)

let%expect_test "infeasible: x in [0, 1], x >= 10" =
  let m = Model.create
    ~vars:[| Var.continuous ~lower:0. ~upper:1. () |]
    ~constraints:[| Constraint.geq ~terms:[(1., 0)] ~rhs:10. () |]
    ()
  in
  let sol = solve_exn m ~options:quiet in
  print_s [%sexp (sol.status : Status.t)];
  [%expect {| Infeasible |}]

let%expect_test "unbounded: max x, x >= 0" =
  let m = Model.create
    ~sense:Maximize
    ~vars:[| Var.continuous ~cost:1. ~lower:0. () |]
    ~constraints:[||]
    ()
  in
  let sol = solve_exn m ~options:{ quiet with presolve = Off } in
  let is_unbounded =
    Status.equal sol.status Unbounded
    || Status.equal sol.status Unbounded_or_infeasible
  in
  printf "unbounded_or_ambiguous=%b\n" is_unbounded;
  [%expect {| unbounded_or_ambiguous=true |}]

(* -- MIP: knapsack -- *)

let%expect_test "10-item knapsack: optimum 309" =
  let weights = [| 23; 31; 29; 44; 53; 38; 63; 85; 89; 82 |] in
  let values  = [| 92; 57; 49; 68; 60; 43; 67; 84; 87; 72 |] in
  let cap = 165 in
  let n = Array.length weights in
  let vars =
    Array.init n ~f:(fun i ->
      Var.binary ~cost:(Float.of_int values.(i)) ())
  in
  let terms =
    List.init n ~f:(fun i -> (Float.of_int weights.(i), i))
  in
  let m = Model.create
    ~sense:Maximize ~vars
    ~constraints:[| Constraint.leq ~terms ~rhs:(Float.of_int cap) () |]
    ()
  in
  let sol = solve_exn m ~options:{ quiet with mip_gap = Some 0. } in
  printf "%s obj=%.0f\n" (Status.to_string sol.status) sol.objective;
  [%expect {| Optimal obj=309 |}]

let%expect_test "changing a var's kind is a new model" =
  let base = Model.create
    ~sense:Maximize
    ~vars:[| Var.continuous ~cost:1. ~lower:0. ~upper:5. () |]
    ~constraints:[| Constraint.leq ~terms:[(1., 0)] ~rhs:3.7 () |]
    ()
  in
  let lp = solve_exn base ~options:quiet in
  let mip_vars = Array.map base.vars ~f:(fun v -> { v with kind = Integer }) in
  let mip = { base with vars = mip_vars } in
  let mip_sol = solve_exn mip ~options:quiet in
  printf "lp=%.2f mip=%.2f\n" lp.objective mip_sol.objective;
  [%expect {| lp=3.70 mip=3.00 |}]

(* -- Options -- *)

let%expect_test "default options" =
  print_s [%sexp (Options.default : Options.t)];
  [%expect {|
    ((time_limit ()) (mip_gap ()) (threads ()) (output false) (solver Auto)
     (presolve Auto) (parallel Auto) (extra ())) |}]

let%expect_test "time_limit accepted" =
  let m = Model.create
    ~vars:[| Var.continuous ~cost:1. () |]
    ~constraints:[| Constraint.geq ~terms:[(1., 0)] ~rhs:0. () |]
    ()
  in
  let opts = { quiet with time_limit = Some 60. } in
  let sol = solve_exn m ~options:opts in
  print_s [%sexp (sol.status : Status.t)];
  [%expect {| Optimal |}]

let%expect_test "unknown option name surfaces in error" =
  let m = Model.create
    ~vars:[| Var.continuous ~cost:1. () |]
    ~constraints:[| Constraint.geq ~terms:[(1., 0)] ~rhs:0. () |]
    ()
  in
  let opts = { quiet with extra = [("totally_bogus", Int 42)] } in
  match solve m ~options:opts with
  | Ok _ -> print_endline "unexpected Ok"
  | Error e ->
    let msg = Error.to_string_hum e in
    printf "mentions_key=%b\n"
      (String.is_substring msg ~substring:"totally_bogus");
    [%expect {| mentions_key=true |}]

let%expect_test "extras: mixed value types" =
  let m = Model.create
    ~vars:[| Var.continuous ~cost:1. ~lower:1. ~upper:10. () |]
    ~constraints:[| Constraint.leq ~terms:[(1., 0)] ~rhs:5. () |]
    ()
  in
  let opts = { quiet with
    extra = [
      ("primal_feasibility_tolerance", Float 1e-7);
      ("random_seed",                  Int 42);
      ("log_to_console",               Bool false);
    ]
  } in
  let sol = solve_exn m ~options:opts in
  print_s [%sexp (sol.status : Status.t)];
  [%expect {| Optimal |}]

(* -- Or_error interface -- *)

let%expect_test "solve returns Ok on success" =
  let m = Model.create
    ~vars:[| Var.continuous ~cost:1. () |]
    ~constraints:[| Constraint.geq ~terms:[(1., 0)] ~rhs:0. () |]
    ()
  in
  (match solve m ~options:quiet with
   | Ok _   -> print_endline "Ok"
   | Error _ -> print_endline "unexpected Error");
  [%expect {| Ok |}]

(* -- File I/O -- *)

let%expect_test "write MPS produces a non-empty file" =
  let m = Model.create ~name:"test"
    ~vars:[|
      Var.continuous ~name:"x" ~cost:1. ~lower:0. ~upper:10. ();
      Var.continuous ~name:"y" ~cost:2. ~lower:0. ~upper:10. ();
    |]
    ~constraints:[|
      Constraint.geq ~name:"c1" ~terms:[(1., 0); (1., 1)] ~rhs:3. ();
    |]
    ()
  in
  let tmp = Stdlib.Filename.temp_file "highs_" ".mps" in
  Exn.protectx tmp
    ~f:(fun tmp ->
      (match write m tmp ~options:quiet with
       | Ok () -> ()
       | Error e -> Error.raise e);
      let ic = Stdlib.open_in tmp in
      let sz = Stdlib.in_channel_length ic in
      Stdlib.close_in ic;
      printf "exists=%b non_empty=%b\n"
        (Stdlib.Sys.file_exists tmp) (sz > 0))
    ~finally:(fun _ -> try Stdlib.Sys.remove tmp with _ -> ());
  [%expect {| exists=true non_empty=true |}]

(* -- GC pressure -- *)

let%expect_test "200 solves don't leak or crash" =
  for _ = 1 to 200 do
    let m = Model.create
      ~vars:[| Var.continuous ~cost:1. () |]
      ~constraints:[| Constraint.geq ~terms:[(1., 0)] ~rhs:0. () |]
      ()
    in
    let (_ : Solution.t) = solve_exn m ~options:quiet in
    ()
  done;
  Stdlib.Gc.compact ();
  Stdlib.Gc.full_major ();
  print_endline "survived";
  [%expect {| survived |}]

