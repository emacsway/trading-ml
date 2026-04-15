(** Finam wire DTOs: decode JSON payloads into domain types.
    This module isolates wire-format concerns from the rest of the system,
    so a switch from REST → gRPC only touches this file. *)

open Core

let decimal_field k j =
  match Yojson.Safe.Util.member k j with
  | `String s -> Decimal.of_string s
  | `Int n -> Decimal.of_int n
  | `Float f -> Decimal.of_float f
  | `Intlit s -> Decimal.of_string s
  | _ -> invalid_arg ("Finam DTO: missing decimal field " ^ k)

(** Minimal ISO-8601 → epoch seconds (UTC). Finam returns Z-suffixed UTC. *)
let parse_iso8601 (s : string) : int64 =
  try
    Scanf.sscanf s "%d-%d-%dT%d:%d:%d"
      (fun y mo d h mi se ->
         (* Days from civil date (Howard Hinnant algorithm). *)
         let y = if mo <= 2 then y - 1 else y in
         let era = (if y >= 0 then y else y - 399) / 400 in
         let yoe = y - era * 400 in
         let m' = if mo > 2 then mo - 3 else mo + 9 in
         let doy = (153 * m' + 2) / 5 + d - 1 in
         let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy in
         let days = era * 146097 + doe - 719468 in
         Int64.(add (mul (of_int days) 86400L)
                  (of_int (h * 3600 + mi * 60 + se))))
  with _ ->
    try Int64.of_string s with _ -> 0L

let candle_of_json j : Candle.t =
  let ts =
    match Yojson.Safe.Util.member "timestamp" j with
    | `String s -> parse_iso8601 s
    | `Int n -> Int64.of_int n
    | `Intlit s -> Int64.of_string s
    | _ -> 0L
  in
  Candle.make ~ts
    ~open_:(decimal_field "open" j)
    ~high:(decimal_field "high" j)
    ~low:(decimal_field "low" j)
    ~close:(decimal_field "close" j)
    ~volume:(decimal_field "volume" j)

let candles_of_json j : Candle.t list =
  let arr = match Yojson.Safe.Util.member "bars" j with
    | `List l -> l
    | _ ->
      match Yojson.Safe.Util.member "candles" j with
      | `List l -> l
      | _ -> []
  in
  List.map candle_of_json arr
