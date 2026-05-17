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
