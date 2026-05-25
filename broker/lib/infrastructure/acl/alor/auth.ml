(** Alor OAuth2 auth.
    Flow:
      1. The user holds a long-lived [refresh_token] (issued in the
         Alor developer portal), carried in {!Config.t}.
      2. [current] exchanges it for a short-lived JWT via
         [POST {oauth_base}/refresh?token=<refresh_token>] — the
         token rides as a query parameter, the body is empty. The
         response JSON carries the access JWT in the [AccessToken]
         field. Alor does not rotate the refresh-token and returns no
         [expires_in], so there is nothing to persist back.
      3. The JWT's own [exp] claim is the authoritative expiry (decoded
         locally, as in {!Finam.Auth}); we cache it in memory until
         [exp - margin].

    Mutex discipline identical to {!Finam.Auth} / {!Bcs.Auth}: the
    stdlib mutex guards the cached state only, never spanning the HTTP
    round-trip, so concurrent Eio fibers on one OS thread can't
    self-deadlock. *)

type jwt = { token : string; expires_at : float (* unix epoch seconds *) }

type t = {
  cfg : Config.t;
  transport : Http_transport.t;
  mutex : Mutex.t;
  mutable state : jwt option;
}

let make ~transport ~cfg = { cfg; transport; mutex = Mutex.create (); state = None }

(** Decode a JWT payload's [exp] claim. [None] on any parse problem;
    callers fall back to a conservative TTL. Mirrors {!Finam.Auth}. *)
let decode_exp (token : string) : float option =
  try
    match String.split_on_char '.' token with
    | _ :: payload_b64 :: _ -> (
        let normalise s =
          let s =
            String.map
              (function
                | '-' -> '+'
                | '_' -> '/'
                | c -> c)
              s
          in
          let pad = (4 - (String.length s mod 4)) mod 4 in
          s ^ String.make pad '='
        in
        let raw = Base64.decode_exn (normalise payload_b64) in
        let j = Yojson.Safe.from_string raw in
        match Yojson.Safe.Util.member "exp" j with
        | `Int n -> Some (float_of_int n)
        | `Float f -> Some f
        | _ -> None)
    | _ -> None
  with _ -> None

let now () = Unix.gettimeofday ()

(** Safety margin: refresh 30 seconds before the stated expiry to
    avoid races with in-flight requests. *)
let margin = 30.0

(** Pure HTTP refresh — does NOT touch [t.state] or the mutex. Returns
    the fresh JWT; the caller publishes it under the lock. *)
let http_refresh t : jwt =
  let url =
    let base = t.cfg.Config.oauth_base in
    let u = Uri.with_path base (Uri.path base ^ "/refresh") in
    Uri.with_query' u [ ("token", t.cfg.refresh_token) ]
  in
  let resp =
    t.transport
      { meth = `POST; url; headers = [ ("Accept", "application/json") ]; body = None }
  in
  if resp.status < 200 || resp.status >= 300 then
    failwith (Printf.sprintf "Alor Auth: /refresh returned %d: %s" resp.status resp.body);
  let j = Yojson.Safe.from_string resp.body in
  let token =
    match Yojson.Safe.Util.member "AccessToken" j with
    | `String s -> s
    | _ -> failwith ("Alor Auth: no AccessToken field in " ^ resp.body)
  in
  let expires_at =
    match decode_exp token with
    | Some exp -> exp
    | None -> now () +. 600.0
  in
  { token; expires_at }

let with_lock t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f

(** Force-drop the cached JWT so the next [current] refreshes. Called
    by the HTTP retry layer on 401. *)
let invalidate (t : t) : unit = with_lock t (fun () -> t.state <- None)

(** Returns a live JWT. Fast path inspects the cache under a tiny
    critical section; slow path drops the lock, does the network call,
    re-acquires briefly to publish. Concurrent stale callers may all
    race the slow path — last write wins, every caller ends with a
    valid token; cheaper than holding a lock across the round-trip. *)
let current (t : t) : string =
  let cached =
    with_lock t (fun () ->
        match t.state with
        | Some jwt when jwt.expires_at -. now () >= margin -> Some jwt
        | _ -> None)
  in
  match cached with
  | Some jwt -> jwt.token
  | None ->
      let fresh = http_refresh t in
      with_lock t (fun () -> t.state <- Some fresh);
      fresh.token
