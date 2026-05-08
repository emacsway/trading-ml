type t = {
  correlation_id : string;
  side : string;
  symbol : string;
  quantity : string;
  price : string;
}
[@@deriving yojson]
