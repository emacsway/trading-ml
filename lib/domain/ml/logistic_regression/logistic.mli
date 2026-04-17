(** Minimal logistic regression: sigmoid, prediction, and online SGD.
    No external dependencies — pure float arithmetic. *)

type t

val make : n_features:int -> ?lr:float -> ?l2:float -> unit -> t
val n_features : t -> int

val sigmoid : float -> float
val predict : t -> float array -> float

val sgd_step : t -> float array -> float -> unit
val train : t -> epochs:int -> (float array * float) list -> float

val export_weights : t -> float array
val of_weights : ?lr:float -> ?l2:float -> float array -> t
