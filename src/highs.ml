(* Functional frontend for HiGHS. All model-building is pure OCaml. The
 * single side-effect is [solve], which allocates a HiGHS handle,
 * populates it from the immutable model, runs the solver, extracts
 * a solution, and releases the handle before returning. *)

(* ============================================================
 * PART 1: Types (all immutable records / variants)
 * ============================================================ *)

type sense = Minimize | Maximize

type var_kind =
  | Continuous
  | Integer
  | Binary
  | Semi_continuous
  | Semi_integer

type var = {
  name : string;
  kind : var_kind;
  lower : float;
  upper : float;
  cost : float;
}

type term = float * int

type constr = {
  name : string;
  lower : float;
  upper : float;
  terms : term list;
}

type model = {
  name : string;
  sense : sense;
  offset : float;
  vars : var array;
  constraints : constr array;
}

type solver = Simplex | Ipm | Pdlp | Auto
type toggle = On | Off | Auto

type option_value =
  | Bool of bool
  | Int of int
  | Float of float
  | String of string

type options = {
  time_limit : float option;
  mip_gap    : float option;
  threads    : int option;
  output     : bool;
  solver     : solver;
  presolve   : toggle;
  parallel   : toggle;
  extra      : (string * option_value) list;
}

let default_options = {
  time_limit = None;
  mip_gap = None;
  threads = None;
  output = false;
  solver = Auto;
  presolve = Auto;
  parallel = Auto;
  extra = [];
}

type status =
  | Optimal
  | Infeasible
  | Unbounded
  | Unbounded_or_infeasible
  | Time_limit
  | Iteration_limit
  | Model_error
  | Interrupted
  | Not_solved
  | Other of string

let status_to_string = function
  | Optimal -> "Optimal"
  | Infeasible -> "Infeasible"
  | Unbounded -> "Unbounded"
  | Unbounded_or_infeasible -> "Unbounded_or_infeasible"
  | Time_limit -> "Time_limit"
  | Iteration_limit -> "Iteration_limit"
  | Model_error -> "Model_error"
  | Interrupted -> "Interrupted"
  | Not_solved -> "Not_solved"
  | Other s -> "Other(" ^ s ^ ")"

let pp_status ppf s = Format.pp_print_string ppf (status_to_string s)

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

exception Solver_error of string
let () = Callback.register_exception "Highs.Solver_error" (Solver_error "")

(* ============================================================
 * PART 2: Constructors (pure)
 * ============================================================ *)

let var ?(name = "") ?(kind = Continuous)
        ?(lower = 0.0) ?(upper = infinity) ?(cost = 0.0) () =
  { name; kind; lower; upper; cost }

let continuous ?(name = "") ?(lower = 0.0) ?(upper = infinity) ?(cost = 0.0) () =
  { name; kind = Continuous; lower; upper; cost }

let integer ?(name = "") ?(lower = 0) ?(upper = max_int) ?(cost = 0.0) () =
  { name; kind = Integer;
    lower = float_of_int lower;
    upper = if upper = max_int then infinity else float_of_int upper;
    cost }

let binary ?(name = "") ?(cost = 0.0) () =
  { name; kind = Binary; lower = 0.0; upper = 1.0; cost }

let eq  ?(name = "") ~terms ~rhs () = { name; lower = rhs; upper = rhs; terms }
let leq ?(name = "") ~terms ~rhs () = { name; lower = neg_infinity; upper = rhs; terms }
let geq ?(name = "") ~terms ~rhs () = { name; lower = rhs; upper = infinity; terms }
let range ?(name = "") ~terms ~lower ~upper () = { name; lower; upper; terms }

let model ?(name = "") ?(sense = Minimize) ?(offset = 0.0)
          ~vars ~constraints () =
  { name; sense; offset; vars; constraints }

(* ============================================================
 * PART 3: FFI primitives (private)
 * All the [caml_highs_*] externals below live in highs_stubs.c.
 * Nothing outside this file should touch them.
 * ============================================================ *)

module Ffi = struct
  (* Opaque HiGHS handle. Custom-block-wrapped; finalizer calls
   * Highs_destroy when the OCaml value becomes unreachable. *)
  type handle

  external create : unit -> handle = "caml_highs_create"

  external set_bool   : handle -> string -> bool  -> unit = "caml_highs_set_bool_option"
  external set_int    : handle -> string -> int   -> unit = "caml_highs_set_int_option"
  external set_double : handle -> string -> float -> unit = "caml_highs_set_double_option"
  external set_string : handle -> string -> string -> unit = "caml_highs_set_string_option"

  external pass_lp :
    handle -> int -> float ->
    float array -> float array -> float array ->
    float array -> float array ->
    int array -> int array -> float array ->
    int -> unit
    = "caml_highs_pass_lp_bytecode" "caml_highs_pass_lp_native"

  external pass_mip :
    handle -> int -> float ->
    float array -> float array -> float array ->
    float array -> float array ->
    int array -> int array -> float array ->
    int -> int array -> unit
    = "caml_highs_pass_mip_bytecode" "caml_highs_pass_mip_native"

  external run              : handle -> int    = "caml_highs_run"
  external model_status     : handle -> int    = "caml_highs_get_model_status"
  external objective_value  : handle -> float  = "caml_highs_get_objective_value"

  external get_solution :
    handle -> float array * float array * float array * float array
    = "caml_highs_get_solution"

  external int64_info : handle -> string -> int64 = "caml_highs_get_int64_info"
  external write_model : handle -> string -> unit = "caml_highs_write_model"
end

(* ============================================================
 * PART 4: Encoding pure records into HiGHS's wire format
 * (also pure — takes a model, returns arrays)
 * ============================================================ *)

let matrix_format_rowwise = 2
let sense_to_int = function Minimize -> 1 | Maximize -> -1

let integrality_to_int = function
  | Continuous -> 0
  | Integer -> 1
  | Semi_continuous -> 2
  | Semi_integer -> 3
  | Binary -> 1  (* HiGHS treats binary as integer with [0,1] bounds *)

(* Row-wise CSR encoding: for each constraint i, a_start.(i) is the
 * offset into a_index/a_value where its terms start. *)
let encode_matrix constraints =
  let num_row = Array.length constraints in
  let nz = Array.fold_left
    (fun acc c -> acc + List.length c.terms) 0 constraints
  in
  let a_start = Array.make (num_row + 1) 0 in
  let a_index = Array.make nz 0 in
  let a_value = Array.make nz 0.0 in
  let pos = ref 0 in
  Array.iteri (fun i c ->
    a_start.(i) <- !pos;
    List.iter (fun (coeff, v) ->
      a_index.(!pos) <- v;
      a_value.(!pos) <- coeff;
      incr pos
    ) c.terms
  ) constraints;
  a_start.(num_row) <- !pos;
  (a_start, a_index, a_value)

let has_integer_vars m =
  Array.exists (fun v -> v.kind <> Continuous) m.vars

let integrality_array m =
  Array.map (fun v -> integrality_to_int v.kind) m.vars

(* Binary vars need lower=0, upper=1 clamped. *)
let effective_bounds v =
  match v.kind with
  | Binary -> (0.0, 1.0)
  | _ -> (v.lower, v.upper)

let col_costs   m = Array.map (fun v -> v.cost) m.vars
let col_lowers  m = Array.map (fun v -> fst (effective_bounds v)) m.vars
let col_uppers  m = Array.map (fun v -> snd (effective_bounds v)) m.vars
let row_lowers  m = Array.map (fun c -> c.lower) m.constraints
let row_uppers  m = Array.map (fun c -> c.upper) m.constraints

(* ============================================================
 * PART 5: Option application (impure but confined)
 * ============================================================ *)

let apply_solver_option h = function
  | Simplex -> Ffi.set_string h "solver" "simplex"
  | Ipm     -> Ffi.set_string h "solver" "ipm"
  | Pdlp    -> Ffi.set_string h "solver" "pdlp"
  | Auto    -> Ffi.set_string h "solver" "choose"

let apply_toggle_option h key = function
  | On     -> Ffi.set_string h key "on"
  | Off    -> Ffi.set_string h key "off"
  | Auto   -> Ffi.set_string h key "choose"

let apply_extra_option h (key, v) =
  match v with
  | Bool b   -> Ffi.set_bool   h key b
  | Int i    -> Ffi.set_int    h key i
  | Float f  -> Ffi.set_double h key f
  | String s -> Ffi.set_string h key s

let apply_options h opts =
  Ffi.set_bool h "output_flag" opts.output;
  Option.iter (Ffi.set_double h "time_limit")  opts.time_limit;
  Option.iter (Ffi.set_double h "mip_rel_gap") opts.mip_gap;
  Option.iter (Ffi.set_int    h "threads")     opts.threads;
  apply_solver_option h opts.solver;
  apply_toggle_option h "presolve" opts.presolve;
  apply_toggle_option h "parallel" opts.parallel;
  List.iter (apply_extra_option h) opts.extra

(* ============================================================
 * PART 6: Status mapping (pure)
 * ============================================================ *)

let status_of_int = function
  |  0 -> Not_solved
  |  1 | 2 | 3 | 4 | 5 -> Model_error
  |  6 -> Not_solved
  |  7 -> Optimal
  |  8 -> Infeasible
  |  9 -> Unbounded_or_infeasible
  | 10 -> Unbounded
  | 11 -> Other "objective_bound"
  | 12 -> Other "objective_target"
  | 13 -> Time_limit
  | 14 -> Iteration_limit
  | 15 -> Other "unknown"
  | 16 -> Other "solution_limit"
  | 17 -> Interrupted
  | n  -> Other (string_of_int n)

let safe_int64_info h key =
  try Ffi.int64_info h key with Solver_error _ -> 0L

(* ============================================================
 * PART 7: The single side-effecting entry point
 * ============================================================ *)

let solve ?(options = default_options) m =
  let h = Ffi.create () in
  apply_options h options;
  let sense = sense_to_int m.sense in
  let costs = col_costs m in
  let col_l = col_lowers m in
  let col_u = col_uppers m in
  let row_l = row_lowers m in
  let row_u = row_uppers m in
  let (a_start, a_index, a_value) = encode_matrix m.constraints in
  (if has_integer_vars m
   then Ffi.pass_mip h sense m.offset costs col_l col_u row_l row_u
          a_start a_index a_value matrix_format_rowwise (integrality_array m)
   else Ffi.pass_lp  h sense m.offset costs col_l col_u row_l row_u
          a_start a_index a_value matrix_format_rowwise);
  let _ = Ffi.run h in
  let (values, duals, row_values, row_duals) = Ffi.get_solution h in
  {
    status = status_of_int (Ffi.model_status h);
    objective = Ffi.objective_value h;
    values;
    duals;
    row_values;
    row_duals;
    simplex_iterations = safe_int64_info h "simplex_iteration_count";
    mip_nodes = safe_int64_info h "mip_node_count";
  }

(* ============================================================
 * PART 8: File I/O
 * ============================================================ *)

let write m path =
  let h = Ffi.create () in
  let sense = sense_to_int m.sense in
  let costs = col_costs m in
  let col_l = col_lowers m in
  let col_u = col_uppers m in
  let row_l = row_lowers m in
  let row_u = row_uppers m in
  let (a_start, a_index, a_value) = encode_matrix m.constraints in
  (if has_integer_vars m
   then Ffi.pass_mip h sense m.offset costs col_l col_u row_l row_u
          a_start a_index a_value matrix_format_rowwise (integrality_array m)
   else Ffi.pass_lp  h sense m.offset costs col_l col_u row_l row_u
          a_start a_index a_value matrix_format_rowwise);
  Ffi.write_model h path

(* ============================================================
 * PART 9: Version
 * ============================================================ *)

module Version = struct
  external string  : unit -> string = "caml_highs_version"
  external major   : unit -> int    = "caml_highs_version_major"
  external minor   : unit -> int    = "caml_highs_version_minor"
  external patch   : unit -> int    = "caml_highs_version_patch"
  external githash : unit -> string = "caml_highs_githash"
end
