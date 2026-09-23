(** OCaml bindings for the {{:https://highs.dev} HiGHS} optimization solver.

    A functional interface written in Jane Street style: each type has its
    own module, records derive [sexp_of], [compare], [equal], and [hash],
    and the recoverable-failure entry points return [_ Or_error.t] with
    exception-throwing [_exn] companions.

    {1 Example}

    {[
      open Base
      open Highs

      let m =
        Model.create
          ~sense:Minimize
          ~vars:[|
            Var.continuous ~name:"bread" ~cost:0.5 ();
            Var.continuous ~name:"milk"  ~cost:0.3 ();
            Var.continuous ~name:"meat"  ~cost:0.7 ();
          |]
          ~constraints:[|
            Constraint.geq ~name:"protein"
              ~terms:[(4., 0); (8., 1); (20., 2)] ~rhs:50. ();
            Constraint.geq ~name:"calcium"
              ~terms:[(2., 0); (12., 1); (3., 2)] ~rhs:30. ();
          |]
          ()
      in
      match solve m with
      | Ok sol -> print_s [%sexp (sol.status : Status.t)]
      | Error e -> print_s [%sexp (e : Error.t)]
    ]} *)

open Base

(** {1 Enums} *)

module Sense : sig
  type t = Minimize | Maximize
  [@@deriving sexp_of, compare, equal, hash]
end

module Var_kind : sig
  type t =
    | Continuous
    | Integer
    | Binary
    | Semi_continuous
    | Semi_integer
  [@@deriving sexp_of, compare, equal, hash]
end

module Solver_algorithm : sig
  type t = Simplex | Ipm | Pdlp | Auto
  [@@deriving sexp_of, compare, equal]
end

module Toggle : sig
  type t = On | Off | Auto
  [@@deriving sexp_of, compare, equal]
end

module Option_value : sig
  type t =
    | Bool of bool
    | Int of int
    | Float of float
    | String of string
  [@@deriving sexp_of]
end

module Status : sig
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

  val to_string : t -> string
end

(** {1 Model components} *)

module Var : sig
  type t = {
    name  : string;
    kind  : Var_kind.t;
    lower : float;
    upper : float;
    cost  : float;
  } [@@deriving sexp_of, compare, equal, fields]

  (** [create ()] builds a decision variable. Defaults: [name = ""],
      [kind = Continuous], [lower = 0.], [upper = infinity], [cost = 0.]. *)
  val create :
    ?name:string ->
    ?kind:Var_kind.t ->
    ?lower:float ->
    ?upper:float ->
    ?cost:float ->
    unit -> t

  val continuous :
    ?name:string -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> t

  val integer :
    ?name:string -> ?lower:float -> ?upper:float -> ?cost:float -> unit -> t

  (** [binary ()] fixes [lower = 0.], [upper = 1.], [kind = Binary]. *)
  val binary : ?name:string -> ?cost:float -> unit -> t
end

module Term : sig
  (** A single term in a linear expression: [(coefficient, variable_index)].
      Read [(4., 0)] as "4 times variable 0". *)
  type t = float * int
  [@@deriving sexp_of, compare, equal]
end

module Constraint : sig
  type t = {
    name  : string;
    lower : float;
    upper : float;
    terms : Term.t list;
  } [@@deriving sexp_of, compare, equal, fields]

  (** [range ~terms ~lower ~upper ()] encodes
      [lower <= sum(terms) <= upper]. *)
  val range :
    ?name:string ->
    terms:Term.t list ->
    lower:float ->
    upper:float ->
    unit -> t

  val eq  : ?name:string -> terms:Term.t list -> rhs:float -> unit -> t
  val leq : ?name:string -> terms:Term.t list -> rhs:float -> unit -> t
  val geq : ?name:string -> terms:Term.t list -> rhs:float -> unit -> t
end

module Model : sig
  type t = {
    name        : string;
    sense       : Sense.t;
    offset      : float;
    vars        : Var.t array;
    constraints : Constraint.t array;
  } [@@deriving sexp_of, compare, equal, fields]

  val create :
    ?name:string ->
    ?sense:Sense.t ->
    ?offset:float ->
    vars:Var.t array ->
    constraints:Constraint.t array ->
    unit -> t

  val has_integer_vars : t -> bool
end

(** {1 Solver options} *)

module Options : sig
  type t = {
    time_limit : float option;      (** seconds *)
    mip_gap    : float option;      (** relative MIP gap tolerance *)
    threads    : int option;
    output     : bool;              (** HiGHS's own log to stdout *)
    solver     : Solver_algorithm.t;
    presolve   : Toggle.t;
    parallel   : Toggle.t;
    extra      : (string * Option_value.t) list;
      (** Any HiGHS option not covered above, keyed by name. Unknown keys
          make [solve] return [Error]. *)
  } [@@deriving sexp_of, fields]

  val default : t
end

(** {1 Solutions} *)

module Solution : sig
  type t = {
    status             : Status.t;
    objective          : float;
    values             : float array;    (** one entry per variable *)
    duals              : float array;    (** dual (reduced cost) per variable *)
    row_values         : float array;    (** one entry per constraint *)
    row_duals          : float array;    (** one entry per constraint *)
    simplex_iterations : Int64.t;
    mip_nodes          : Int64.t;
  } [@@deriving sexp_of, fields]
end

(** {1 Errors} *)

(** Raised by [_exn] variants when HiGHS reports an internal error.
    The [Or_error]-returning variants convert this exception into an
    [Error] value. *)
exception Solver_error of string

(** {1 The core operations} *)

(** Solve a model. Returns the fresh {!Solution.t} on success. The
    HiGHS handle is created, used, and released inside this call.

    [Solver_error] is caught and returned as [Error]. Infeasible and
    unbounded outcomes are NOT errors: they are reported through
    {!Solution.status}. *)
val solve : ?options:Options.t -> Model.t -> Solution.t Or_error.t

(** Exception-raising variant of {!solve}.
    @raise Solver_error on any HiGHS internal error. *)
val solve_exn : ?options:Options.t -> Model.t -> Solution.t

(** Write the model to an MPS or LP file (format chosen by extension).
    Options are applied before writing so [output = false] silences the
    HiGHS banner. *)
val write : ?options:Options.t -> Model.t -> string -> unit Or_error.t

(** Exception-raising variant of {!write}.
    @raise Solver_error if the file cannot be written. *)
val write_exn : ?options:Options.t -> Model.t -> string -> unit

(** {1 Version} *)

module Version : sig
  val string  : unit -> string
  val major   : unit -> int
  val minor   : unit -> int
  val patch   : unit -> int
  val githash : unit -> string
end
