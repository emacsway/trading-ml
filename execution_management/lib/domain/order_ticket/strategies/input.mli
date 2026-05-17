(** Strategy input event — the union of all stimuli a strategy
    can react to. The aggregate translates each domain event (clock
    tick, broker IE, volume bar, market-data quote) into the
    corresponding [Input.t] and feeds it to the embedded strategy.

    Eight constructors:
    - [Tick]: scheduler-driven, consumed by TWAP / VWAP / IS;
    - [Volume_bar]: volume-feed-driven, consumed by POV;
    - [Price_quote]: market-data-driven, consumed by IS (adaptive
      refinement on adverse price movement);
    - [Placement_acknowledged]: broker accepted the submit;
    - [Placement_filled]: broker reported a fill (full or partial);
    - [Placement_rejected]: broker refused the slice;
    - [Placement_unreachable]: transport failure on the slice;
    - [Placement_cancelled]: broker confirmed the cancel.

    Strategies are not required to handle every constructor;
    irrelevant ones return [Decision.empty] with the state
    unchanged. *)

type t =
  | Tick of { now : int64 }
  | Volume_bar of { bar : Values.Volume_bar.t }
  | Price_quote of { quote : Values.Market_data_quote.t }
  | Placement_acknowledged of { placement_id : Placement.Values.Placement_id.t }
  | Placement_filled of {
      placement_id : Placement.Values.Placement_id.t;
      fill : Placement.Values.Fill_record.t;
    }
  | Placement_rejected of {
      placement_id : Placement.Values.Placement_id.t;
      reason : string;
    }
  | Placement_unreachable of { placement_id : Placement.Values.Placement_id.t }
  | Placement_cancelled of { placement_id : Placement.Values.Placement_id.t }
