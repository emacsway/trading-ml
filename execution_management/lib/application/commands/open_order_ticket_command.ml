type directive = { kind : string; params : string option }

type t = {
  reservation_id : int;
  correlation_id : string;
  book_id : string;
  symbol : string;
  side : string;
  quantity : string;
  directive : directive option;
}
