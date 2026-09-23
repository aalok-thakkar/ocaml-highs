(** OCaml bindings for the HiGHS optimization solver.

    A functional interface: an optimization problem is a value of type
    {!type-model} built from immutable records, and {!solve} is the only
    operation that talks to HiGHS. Every other function in this module
    is a pure OCaml constructor.

    {1 Quick example: a diet problem}

    {[
      let m =
        Highs.model
          ~sense:Highs.Minimize
          ~vars:[|
            Highs.continuous ~name:"bread" ~cost:0.5 ~lower:0.0 ();
            Highs.continuous ~name:"milk"  ~cost:0.3 ~lower:0.0 ();
            Highs.continuous ~name:"meat"  ~cost:0.7 ~lower:0.0 ();
          |]
          ~constraints:[|
            Highs.geq ~name:"protein"
              ~terms:[(4.0, 0); (8.0, 1); (20.0, 2)] ~rhs:50.0 ();
            Highs.geq ~name:"calcium"
              ~terms:[(2.0, 0); (12.0, 1); (3.0, 2)] ~rhs:30.0 ();
          |]
          ()
      in
      let sol = Highs.solve m in
      match sol.status with
      | Highs.Optimal ->
        Printf.printf "cost = %.4f\n" sol.objective;
        Array.iter (Printf.printf "  %f\n") sol.values
      | s -> Printf.printf "no optimum: %s\n" (Highs.status_to_string s)
    ]} *)

(** {1 Objective sense} *)

type sense = Minimize | Maximize

(** {1 Variables} *)

(** What values a variable can take. *)
type var_kind =
  | Continuous     (** any real in [lower, upper] *)
  | Integer        (** any integer in [lower, upper] *)
  | Binary         (** 0 or 1 (lower and upper ignored) *)
  | Semi_continuous (** 0, or any real in [lower, upper] *)
  | Semi_integer    (** 0, or any integer in [lower, upper] *)

type var = {
  name : string;   (** empty string if unnamed *)
  kind : var_kind;
  lower : float;   (** use [neg_infinity] for no lower bound *)
  upper : float;   (** use [infinity] for no upper bound *)
  cost : float;    (** coefficient in the objective *)
}

(** {2 Variable constructors} *)

val var :
  ?name:string ->
  ?kind:var_kind ->
  ?lower:float ->
  ?upper:float ->
  ?cost:float ->
  unit -> var
(** General constructor. Defaults: [name = ""], [kind = Continuous],
    [lower = 0.0], [upper = infinity], [cost = 0.0]. *)

val continuous :
  ?name:string -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> var

val integer :
  ?name:string -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> var

val binary : ?name:string -> ?cost:float -> unit -> var

(** {1 Constraints}

    A term is a pair [(coefficient, variable_index)]. Read [(4.0, 0)] as
    "4.0 times variable 0". *)

type term = float * int

type constr = {
  name : string;
  lower : float;
  upper : float;
  terms : term list;
}

(** {2 Constraint constructors} *)

val eq  : ?name:string -> terms:term list -> rhs:float -> unit -> constr
(** [eq ~terms ~rhs ()] encodes [sum(terms) = rhs]. *)

val leq : ?name:string -> terms:term list -> rhs:float -> unit -> constr
(** [leq ~terms ~rhs ()] encodes [sum(terms) <= rhs]. *)

val geq : ?name:string -> terms:term list -> rhs:float -> unit -> constr
(** [geq ~terms ~rhs ()] encodes [sum(terms) >= rhs]. *)

val range :
  ?name:string -> terms:term list -> lower:float -> upper:float -> unit -> constr
(** [range ~terms ~lower ~upper ()] encodes [lower <= sum(terms) <= upper]. *)

(** {1 Models} *)

type model = {
  name : string;
  sense : sense;
  offset : float;                (** constant added to the objective *)
  vars : var array;
  constraints : constr array;
}

val model :
  ?name:string ->
  ?sense:sense ->
  ?offset:float ->
  vars:var array ->
  constraints:constr array ->
  unit ->
  model
(** Assemble a model. Defaults: [name = ""], [sense = Minimize],
    [offset = 0.0]. *)

(** {1 Solver options} *)

(** LP algorithm to use. *)
type solver = Simplex | Ipm | Pdlp | Auto

(** For yes/no/let-HiGHS-decide options. *)
type toggle = On | Off | Auto

(** For the [extra] option escape hatch. *)
type option_value =
  | Bool of bool
  | Int of int
  | Float of float
  | String of string

type options = {
  time_limit : float option;   (** seconds *)
  mip_gap    : float option;   (** relative MIP gap tolerance *)
  threads    : int option;
  output     : bool;           (** HiGHS's own log to stdout *)
  solver     : solver;
  presolve   : toggle;
  parallel   : toggle;
  extra      : (string * option_value) list;
    (** Any HiGHS option not covered above, keyed by name. *)
}

val default_options : options
(** Sensible defaults: no time limit, [mip_gap] left to HiGHS's default,
    all threads, [output = false], everything else on [Auto], no extras. *)

(** {1 Status of a completed solve} *)

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
    (** A HiGHS model-status we don't map explicitly (rare). *)

val status_to_string : status -> string
val pp_status : Format.formatter -> status -> unit

(** {1 Solution} *)

type solution = {
  status : status;
  objective : float;
  values : float array;         (** one entry per variable *)
  duals : float array;          (** dual (reduced cost) per variable *)
  row_values : float array;     (** one entry per constraint *)
  row_duals : float array;      (** one entry per constraint *)
  simplex_iterations : int64;
  mip_nodes : int64;
}

(** {1 Errors} *)

exception Solver_error of string
(** Raised when HiGHS reports an internal error during {!solve},
    {!write}, or option application. The string contains the operation
    name and the offending key or path when applicable. *)

(** {1 The core operation} *)

val solve : ?options:options -> model -> solution
(** Solve a model. This is the only function that has side effects
    (allocating a HiGHS handle, running the solver). It returns a fresh
    {!type-solution} record; the handle is released before returning.

    @raise Solver_error on any HiGHS error during option setup, model
    loading, or solve. Infeasible and unbounded outcomes are NOT errors;
    they are reported through {!type-status}. *)

(** {1 File I/O} *)

val write : model -> string -> unit
(** Write the model to an MPS or LP file (format chosen by extension).

    @raise Solver_error if the file cannot be written. *)

(** {1 Version} *)

module Version : sig
  val string  : unit -> string
  val major   : unit -> int
  val minor   : unit -> int
  val patch   : unit -> int
  val githash : unit -> string
end
