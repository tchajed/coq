(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *   INRIA, CNRS and contributors - Copyright 1999-2018       *)
(* <O___,, *       (see CREDITS file for the list of authors)           *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

open Names
open Extend
open Vernacexpr
open Genarg
open Constrexpr
open Libnames
open Misctypes
open Genredexpr

(** The parser of Coq *)

module Gram : sig

  include Grammar.S with type te = Tok.t

(* Where Grammar.S is

module type S =
  sig
    type te = 'x;
    type parsable = 'x;
    value parsable : Stream.t char -> parsable;
    value tokens : string -> list (string * int);
    value glexer : Plexing.lexer te;
    value set_algorithm : parse_algorithm -> unit;
    module Entry :
      sig
        type e 'a = 'y;
        value create : string -> e 'a;
        value parse : e 'a -> parsable -> 'a;
        value parse_token : e 'a -> Stream.t te -> 'a;
        value name : e 'a -> string;
        value of_parser : string -> (Stream.t te -> 'a) -> e 'a;
        value print : Format.formatter -> e 'a -> unit;
        external obj : e 'a -> Gramext.g_entry te = "%identity";
      end
    ;
    module Unsafe :
      sig
        value gram_reinit : Plexing.lexer te -> unit;
        value clear_entry : Entry.e 'a -> unit;
      end
    ;
    value extend :
      Entry.e 'a -> option Gramext.position ->
        list
          (option string * option Gramext.g_assoc *
           list (list (Gramext.g_symbol te) * Gramext.g_action)) ->
        unit;
    value delete_rule : Entry.e 'a -> list (Gramext.g_symbol te) -> unit;
  end

*)

  type 'a entry = 'a Entry.e
  type internal_entry = Tok.t Gramext.g_entry
  type symbol = Tok.t Gramext.g_symbol
  type action = Gramext.g_action
  type production_rule = symbol list * action
  type single_extend_statment =
      string option * Gramext.g_assoc option * production_rule list
  type extend_statment =
      Gramext.position option * single_extend_statment list

  type coq_parsable

  val parsable : ?file:Loc.source -> char Stream.t -> coq_parsable
  val action : 'a -> action
  val entry_create : string -> 'a entry
  val entry_parse : 'a entry -> coq_parsable -> 'a
  val entry_print : Format.formatter -> 'a entry -> unit

  (* Get comment parsing information from the Lexer *)
  val comment_state : coq_parsable -> ((int * int) * string) list

  (* Apparently not used *)
  val srules' : production_rule list -> symbol
  val parse_tokens_after_filter : 'a entry -> Tok.t Stream.t -> 'a

end with type 'a Entry.e = 'a Grammar.GMake(CLexer).Entry.e

(** The parser of Coq is built from three kinds of rule declarations:

   - dynamic rules declared at the evaluation of Coq files (using
     e.g. Notation, Infix, or Tactic Notation)
   - static rules explicitly defined in files g_*.ml4
   - static rules macro-generated by ARGUMENT EXTEND, TACTIC EXTEND and
     VERNAC EXTEND (see e.g. file extratactics.ml4)
*)

(** Dynamic extension of rules

    For constr notations, dynamic addition of new rules is done in
    several steps:

    - "x + y" (user gives a notation string of type Topconstr.notation)
        |     (together with a constr entry level, e.g. 50, and indications of)
        |     (subentries, e.g. x in constr next level and y constr same level)
        |
        | splitting into tokens by Metasyntax.split_notation_string
        V
      [String "x"; String "+"; String "y"] : symbol_token list
        |
        | interpreted as a mixed parsing/printing production
        | by Metasyntax.analyse_notation_tokens
        V
      [NonTerminal "x"; Terminal "+"; NonTerminal "y"] : symbol list
        |
        | translated to a parsing production by Metasyntax.make_production
        V
      [GramConstrNonTerminal (ETConstr (NextLevel,(BorderProd Left,LeftA)),
                              Some "x");
       GramConstrTerminal ("","+");
       GramConstrNonTerminal (ETConstr (NextLevel,(BorderProd Right,LeftA)),
                              Some "y")]
       : grammar_constr_prod_item list
        |
        | Egrammar.make_constr_prod_item
        V
      Gramext.g_symbol list which is sent to camlp5

    For user level tactic notations, dynamic addition of new rules is
    also done in several steps:

    - "f" constr(x) (user gives a Tactic Notation command)
        |
        | parsing
        V
      [TacTerm "f"; TacNonTerm ("constr", Some "x")]
      : grammar_tactic_prod_item_expr list
        |
        | Metasyntax.interp_prod_item
        V
      [GramTerminal "f";
       GramNonTerminal (ConstrArgType, Aentry ("constr","constr"), Some "x")]
      : grammar_prod_item list
        |
        | Egrammar.make_prod_item
        V
      Gramext.g_symbol list

    For TACTIC/VERNAC/ARGUMENT EXTEND, addition of new rules is done as follows:

    - "f" constr(x) (developer gives an EXTEND rule)
        |
        | macro-generation in tacextend.ml4/vernacextend.ml4/argextend.ml4
        V
      [GramTerminal "f";
       GramNonTerminal (ConstrArgType, Aentry ("constr","constr"), Some "x")]
        |
        | Egrammar.make_prod_item
        V
      Gramext.g_symbol list

*)

(** Temporarily activate camlp5 verbosity *)

val camlp5_verbosity : bool -> ('a -> unit) -> 'a -> unit

(** Parse a string *)

val parse_string : 'a Gram.entry -> string -> 'a
val eoi_entry : 'a Gram.entry -> 'a Gram.entry
val map_entry : ('a -> 'b) -> 'a Gram.entry -> 'b Gram.entry

type gram_universe

val get_univ : string -> gram_universe

val uprim : gram_universe
val uconstr : gram_universe
val utactic : gram_universe
val uvernac : gram_universe

val register_grammar : ('raw, 'glb, 'top) genarg_type -> 'raw Gram.entry -> unit
val genarg_grammar : ('raw, 'glb, 'top) genarg_type -> 'raw Gram.entry

val create_generic_entry : gram_universe -> string ->
  ('a, rlevel) abstract_argument_type -> 'a Gram.entry

module Prim :
  sig
    open Names
    open Libnames
    val preident : string Gram.entry
    val ident : Id.t Gram.entry
    val name : lname Gram.entry
    val identref : lident Gram.entry
    val univ_decl : universe_decl_expr Gram.entry
    val ident_decl : ident_decl Gram.entry
    val pattern_ident : Id.t Gram.entry
    val pattern_identref : lident Gram.entry
    val base_ident : Id.t Gram.entry
    val natural : int Gram.entry
    val bigint : Constrexpr.raw_natural_number Gram.entry
    val integer : int Gram.entry
    val string : string Gram.entry
    val lstring : lstring Gram.entry
    val qualid : qualid CAst.t Gram.entry
    val fullyqualid : Id.t list CAst.t Gram.entry
    val reference : reference Gram.entry
    val by_notation : (string * string option) Gram.entry
    val smart_global : reference or_by_notation Gram.entry
    val dirpath : DirPath.t Gram.entry
    val ne_string : string Gram.entry
    val ne_lstring : lstring Gram.entry
    val var : lident Gram.entry
  end

module Constr :
  sig
    val constr : constr_expr Gram.entry
    val constr_eoi : constr_expr Gram.entry
    val lconstr : constr_expr Gram.entry
    val binder_constr : constr_expr Gram.entry
    val operconstr : constr_expr Gram.entry
    val ident : Id.t Gram.entry
    val global : reference Gram.entry
    val universe_level : glob_level Gram.entry
    val sort : glob_sort Gram.entry
    val sort_family : Sorts.family Gram.entry
    val pattern : cases_pattern_expr Gram.entry
    val constr_pattern : constr_expr Gram.entry
    val lconstr_pattern : constr_expr Gram.entry
    val closed_binder : local_binder_expr list Gram.entry
    val binder : local_binder_expr list Gram.entry (* closed_binder or variable *)
    val binders : local_binder_expr list Gram.entry (* list of binder *)
    val open_binders : local_binder_expr list Gram.entry
    val binders_fixannot : (local_binder_expr list * (lident option * recursion_order_expr)) Gram.entry
    val typeclass_constraint : (lname * bool * constr_expr) Gram.entry
    val record_declaration : constr_expr Gram.entry
    val appl_arg : (constr_expr * explicitation CAst.t option) Gram.entry
  end

module Module :
  sig
    val module_expr : module_ast Gram.entry
    val module_type : module_ast Gram.entry
  end

module Vernac_ :
  sig
    val gallina : vernac_expr Gram.entry
    val gallina_ext : vernac_expr Gram.entry
    val command : vernac_expr Gram.entry
    val syntax : vernac_expr Gram.entry
    val vernac_control : vernac_control Gram.entry
    val rec_definition : (fixpoint_expr * decl_notation list) Gram.entry
    val noedit_mode : vernac_expr Gram.entry
    val command_entry : vernac_expr Gram.entry
    val red_expr : raw_red_expr Gram.entry
    val hint_info : Typeclasses.hint_info_expr Gram.entry
  end

(** The main entry: reads an optional vernac command *)
val main_entry : (Loc.t * vernac_control) option Gram.entry

(** Handling of the proof mode entry *)
val get_command_entry : unit -> vernac_expr Gram.entry
val set_command_entry : vernac_expr Gram.entry -> unit

val epsilon_value : ('a -> 'self) -> ('self, 'a) Extend.symbol -> 'self option

(** {5 Extending the parser without synchronization} *)

type gram_reinit = gram_assoc * gram_position
(** Type of reinitialization data *)

val grammar_extend : 'a Gram.entry -> gram_reinit option ->
  'a Extend.extend_statment -> unit
(** Extend the grammar of Coq, without synchronizing it with the backtracking
    mechanism. This means that grammar extensions defined this way will survive
    an undo. *)

(** {5 Extending the parser with summary-synchronized commands} *)

module GramState : Store.S
(** Auxiliary state of the grammar. Any added data must be marshallable. *)

type 'a grammar_command
(** Type of synchronized parsing extensions. The ['a] type should be
    marshallable. *)

type extend_rule =
| ExtendRule : 'a Gram.entry * gram_reinit option * 'a extend_statment -> extend_rule

type 'a grammar_extension = 'a -> GramState.t -> extend_rule list * GramState.t
(** Grammar extension entry point. Given some ['a] and a current grammar state,
    such a function must produce the list of grammar extensions that will be
    applied in the same order and kept synchronized w.r.t. the summary, together
    with a new state. It should be pure. *)

val create_grammar_command : string -> 'a grammar_extension -> 'a grammar_command
(** Create a new grammar-modifying command with the given name. The extension
    function is called to generate the rules for a given data. *)

val extend_grammar_command : 'a grammar_command -> 'a -> unit
(** Extend the grammar of Coq with the given data. *)

val recover_grammar_command : 'a grammar_command -> 'a list
(** Recover the current stack of grammar extensions. *)

val with_grammar_rule_protection : ('a -> 'b) -> 'a -> 'b

(** Location Utils  *)
val to_coqloc : Ploc.t -> Loc.t
val (!@) : Ploc.t -> Loc.t

type frozen_t
val parser_summary_tag : frozen_t Summary.Dyn.tag

(** Registering grammars by name *)

type any_entry = AnyEntry : 'a Gram.entry -> any_entry

val register_grammars_by_name : string -> any_entry list -> unit
val find_grammars_by_name : string -> any_entry list
