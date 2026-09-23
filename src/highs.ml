open Base

(* -- Enums ---------------------------------------------------------- *)

module Sense = struct
  type t = Minimize | Maximize
  [@@deriving sexp_of, compare, equal, hash]

  let to_int = function
    | Minimize -> 1
    | Maximize -> -1
end

module Var_kind = struct
  type t =
    | Continuous
    | Integer
    | Binary
    | Semi_continuous
    | Semi_integer
  [@@deriving sexp_of, compare, equal, hash]

  let to_int = function
    | Continuous      -> 0
    | Integer         -> 1
    | Semi_continuous -> 2
    | Semi_integer    -> 3
    | Binary          -> 1
end

module Solver_algorithm = struct
  type t = Simplex | Ipm | Pdlp | Auto
  [@@deriving sexp_of, compare, equal]

  let to_option_string = function
    | Simplex -> "simplex"
    | Ipm     -> "ipm"
    | Pdlp    -> "pdlp"
    | Auto    -> "choose"
end

module Toggle = struct
  type t = On | Off | Auto
  [@@deriving sexp_of, compare, equal]

  let to_option_string = function
    | On   -> "on"
    | Off  -> "off"
    | Auto -> "choose"
end

module Option_value = struct
  type t =
    | Bool of bool
    | Int of int
    | Float of float
    | String of string
  [@@deriving sexp_of]
end

module Status = struct
  type t =
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
  [@@deriving sexp_of, compare, equal]

  let to_string = function
    | Optimal                 -> "Optimal"
    | Infeasible              -> "Infeasible"
    | Unbounded               -> "Unbounded"
    | Unbounded_or_infeasible -> "Unbounded_or_infeasible"
    | Time_limit              -> "Time_limit"
    | Iteration_limit         -> "Iteration_limit"
    | Model_error             -> "Model_error"
    | Interrupted             -> "Interrupted"
    | Not_solved              -> "Not_solved"
    | Other s                 -> "Other(" ^ s ^ ")"

  let of_int = function
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
    | n  -> Other (Int.to_string n)
end

(* -- Records -------------------------------------------------------- *)

module Var = struct
  type t = {
    name  : string;
    kind  : Var_kind.t;
    lower : float;
    upper : float;
    cost  : float;
  } [@@deriving sexp_of, compare, equal, fields]

  let create ?(name = "") ?(kind = Var_kind.Continuous)
             ?(lower = 0.) ?(upper = Float.infinity) ?(cost = 0.) () =
    { name; kind; lower; upper; cost }

  let continuous ?name ?lower ?upper ?cost () =
    create ?name ~kind:Continuous ?lower ?upper ?cost ()

  let integer ?name ?lower ?upper ?cost () =
    create ?name ~kind:Integer ?lower ?upper ?cost ()

  let binary ?(name = "") ?(cost = 0.) () =
    create ~name ~kind:Binary ~lower:0. ~upper:1. ~cost ()

  let effective_bounds t =
    match t.kind with
    | Binary -> (0., 1.)
    | _      -> (t.lower, t.upper)
end

module Term = struct
  (* A single [(coefficient, variable_index)] pair inside a constraint's
     linear expression. Kept as a pair for terseness. *)
  type t = float * int
  [@@deriving sexp_of, compare, equal]
end

module Constraint = struct
  type t = {
    name  : string;
    lower : float;
    upper : float;
    terms : Term.t list;
  } [@@deriving sexp_of, compare, equal, fields]

  let range ?(name = "") ~terms ~lower ~upper () =
    { name; lower; upper; terms }

  let eq ?name ~terms ~rhs () =
    range ?name ~terms ~lower:rhs ~upper:rhs ()

  let leq ?name ~terms ~rhs () =
    range ?name ~terms ~lower:Float.neg_infinity ~upper:rhs ()

  let geq ?name ~terms ~rhs () =
    range ?name ~terms ~lower:rhs ~upper:Float.infinity ()
end

module Model = struct
  type t = {
    name        : string;
    sense       : Sense.t;
    offset      : float;
    vars        : Var.t array;
    constraints : Constraint.t array;
  } [@@deriving sexp_of, compare, equal, fields]

  let create ?(name = "") ?(sense = Sense.Minimize) ?(offset = 0.)
             ~vars ~constraints () =
    { name; sense; offset; vars; constraints }

  let has_integer_vars t =
    Array.exists t.vars ~f:(fun v ->
      not (Var_kind.equal v.kind Continuous))
end

module Options = struct
  type t = {
    time_limit : float option;
    mip_gap    : float option;
    threads    : int option;
    output     : bool;
    solver     : Solver_algorithm.t;
    presolve   : Toggle.t;
    parallel   : Toggle.t;
    extra      : (string * Option_value.t) list;
  } [@@deriving sexp_of, fields]

  let default = {
    time_limit = None;
    mip_gap    = None;
    threads    = None;
    output     = false;
    solver     = Auto;
    presolve   = Auto;
    parallel   = Auto;
    extra      = [];
  }
end

module Solution = struct
  type t = {
    status             : Status.t;
    objective          : float;
    values             : float array;
    duals              : float array;
    row_values         : float array;
    row_duals          : float array;
    simplex_iterations : Int64.t;
    mip_nodes          : Int64.t;
  } [@@deriving sexp_of, fields]
end

(* -- Errors --------------------------------------------------------- *)

exception Solver_error of string
let () = Stdlib.Callback.register_exception "Highs.Solver_error" (Solver_error "")

(* -- Version -------------------------------------------------------- *)

module Version = struct
  external string  : unit -> string = "caml_highs_version"
  external major   : unit -> int    = "caml_highs_version_major"
  external minor   : unit -> int    = "caml_highs_version_minor"
  external patch   : unit -> int    = "caml_highs_version_patch"
  external githash : unit -> string = "caml_highs_githash"
end

(* -- FFI (private) -------------------------------------------------- *)

module Ffi = struct
  type handle

  external create : unit -> handle = "caml_highs_create"

  external set_bool   : handle -> string -> bool   -> unit = "caml_highs_set_bool_option"
  external set_int    : handle -> string -> int    -> unit = "caml_highs_set_int_option"
  external set_double : handle -> string -> float  -> unit = "caml_highs_set_double_option"
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

  external run             : handle -> int   = "caml_highs_run"
  external model_status    : handle -> int   = "caml_highs_get_model_status"
  external objective_value : handle -> float = "caml_highs_get_objective_value"

  external get_solution :
    handle -> float array * float array * float array * float array
    = "caml_highs_get_solution"

  external int64_info  : handle -> string -> int64 = "caml_highs_get_int64_info"
  external write_model : handle -> string -> unit  = "caml_highs_write_model"
end

(* -- Model encoding ------------------------------------------------- *)

let matrix_format_rowwise = 2

(* Row-wise CSR: a_start.(i) is where row i's terms begin in
   a_index / a_value; a_start.(num_row) is the total nz count. *)
let encode_matrix (constraints : Constraint.t array) =
  let num_row = Array.length constraints in
  let nz =
    Array.fold constraints ~init:0 ~f:(fun acc c -> acc + List.length c.terms)
  in
  let a_start = Array.create ~len:(num_row + 1) 0 in
  let a_index = Array.create ~len:nz 0 in
  let a_value = Array.create ~len:nz 0.0 in
  let pos = ref 0 in
  Array.iteri constraints ~f:(fun i c ->
    a_start.(i) <- !pos;
    List.iter c.terms ~f:(fun (coeff, v) ->
      a_index.(!pos) <- v;
      a_value.(!pos) <- coeff;
      Int.incr pos));
  a_start.(num_row) <- !pos;
  (a_start, a_index, a_value)

let pass_model h (m : Model.t) =
  let sense = Sense.to_int m.sense in
  let costs = Array.map m.vars ~f:Var.cost in
  let col_l =
    Array.map m.vars ~f:(fun v -> fst (Var.effective_bounds v))
  in
  let col_u =
    Array.map m.vars ~f:(fun v -> snd (Var.effective_bounds v))
  in
  let row_l = Array.map m.constraints ~f:Constraint.lower in
  let row_u = Array.map m.constraints ~f:Constraint.upper in
  let (a_start, a_index, a_value) = encode_matrix m.constraints in
  match Model.has_integer_vars m with
  | true ->
    let integ = Array.map m.vars ~f:(fun v -> Var_kind.to_int v.kind) in
    Ffi.pass_mip h sense m.offset costs col_l col_u row_l row_u
      a_start a_index a_value matrix_format_rowwise integ
  | false ->
    Ffi.pass_lp h sense m.offset costs col_l col_u row_l row_u
      a_start a_index a_value matrix_format_rowwise

(* -- Options -------------------------------------------------------- *)

let apply_extra h (key, v) =
  match (v : Option_value.t) with
  | Bool b   -> Ffi.set_bool   h key b
  | Int i    -> Ffi.set_int    h key i
  | Float f  -> Ffi.set_double h key f
  | String s -> Ffi.set_string h key s

let apply_options h (o : Options.t) =
  Ffi.set_bool h "output_flag" o.output;
  Option.iter o.time_limit ~f:(Ffi.set_double h "time_limit");
  Option.iter o.mip_gap    ~f:(Ffi.set_double h "mip_rel_gap");
  Option.iter o.threads    ~f:(Ffi.set_int    h "threads");
  Ffi.set_string h "solver"   (Solver_algorithm.to_option_string o.solver);
  Ffi.set_string h "presolve" (Toggle.to_option_string o.presolve);
  Ffi.set_string h "parallel" (Toggle.to_option_string o.parallel);
  List.iter o.extra ~f:(apply_extra h)

let safe_int64_info h key =
  try Ffi.int64_info h key with Solver_error _ -> 0L

(* -- Public operations ---------------------------------------------- *)

let solve_exn ?(options = Options.default) m =
  let h = Ffi.create () in
  apply_options h options;
  pass_model h m;
  let (_ : int) = Ffi.run h in
  let (values, duals, row_values, row_duals) = Ffi.get_solution h in
  { Solution.
    status             = Status.of_int (Ffi.model_status h)
  ; objective          = Ffi.objective_value h
  ; values
  ; duals
  ; row_values
  ; row_duals
  ; simplex_iterations = safe_int64_info h "simplex_iteration_count"
  ; mip_nodes          = safe_int64_info h "mip_node_count"
  }

let solve ?options m =
  Or_error.try_with (fun () -> solve_exn ?options m)

let write_exn ?(options = Options.default) m path =
  let h = Ffi.create () in
  apply_options h options;
  pass_model h m;
  Ffi.write_model h path

let write ?options m path =
  Or_error.try_with (fun () -> write_exn ?options m path)
