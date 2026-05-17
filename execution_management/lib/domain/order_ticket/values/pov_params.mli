(** POV — Percent Of Volume — parameters.

    Targets [participation_rate × cumulative_observed_volume] as
    the cumulative emitted quantity. Each incoming [Volume_bar]
    grows the observed volume and unlocks a (potentially zero)
    further emission to maintain the rate. The volume feed is
    deferred today; with the [Disabled] adapter POV observably
    waits rather than silently executing as Immediate.

    Invariants:
    - [0 < participation_rate ≤ 1]. *)

type t = private { participation_rate : float }

val make : participation_rate:float -> t
(*@ r = make ~participation_rate
    requires participation_rate > 0.0 /\ participation_rate <= 1.0
    ensures r.participation_rate = participation_rate *)
