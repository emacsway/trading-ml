(** Inbound CQRS command to (re)define a
    {!Portfolio_management.Pair_mean_reversion} policy state for
    one book. Persists the initialised state into the registry
    consulted by {!Apply_bar_command_workflow}.

    Re-issuing for the same [(book_id, pair)] replaces the state
    (resets the rolling window and direction); this matches the
    operator intent "redefine the policy with these parameters
    from now on". *)

include module type of struct
  include Define_pair_mr_command_t
  include Define_pair_mr_command_j
end

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
