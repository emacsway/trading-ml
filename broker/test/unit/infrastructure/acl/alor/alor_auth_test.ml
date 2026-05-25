(** Unit tests for the Alor OAuth refresh flow. A fake transport
    captures requests and replies with canned [AccessToken] JWTs; the
    JWT's [exp] claim drives caching (no [expires_in] from Alor). *)

open Alor

let make_jwt ~exp_epoch =
  let b64url s =
    Base64.encode_string s |> String.to_seq
    |> Seq.filter (fun c -> c <> '=')
    |> String.of_seq
    |> String.map (function
      | '+' -> '-'
      | '/' -> '_'
      | c -> c)
  in
  let header = b64url {|{"alg":"HS256","typ":"JWT"}|} in
  let payload = b64url (Printf.sprintf {|{"exp":%d}|} exp_epoch) in
  Printf.sprintf "%s.%s.%s" header payload (b64url "sig")

let body token = Yojson.Safe.to_string (`Assoc [ ("AccessToken", `String token) ])

let make_cfg () =
  Config.make
    ~oauth_base:(Uri.of_string "https://oauth.test")
    ~refresh_token:"R" ~portfolio:"P" ()

let test_first_call_posts_refresh () =
  let requests = ref [] in
  let token = make_jwt ~exp_epoch:(int_of_float (Unix.gettimeofday ()) + 600) in
  let transport : Http_transport.t =
   fun req ->
    requests := req :: !requests;
    { status = 200; body = body token }
  in
  let auth = Auth.make ~transport ~cfg:(make_cfg ()) in
  Alcotest.(check string) "AccessToken passed through" token (Auth.current auth);
  Alcotest.(check int) "one request fired" 1 (List.length !requests);
  let req = List.hd !requests in
  Alcotest.(check bool) "POST" true (req.meth = `POST);
  Alcotest.(check bool)
    "path ends /refresh" true
    (let p = Uri.path req.url in
     String.length p >= 8 && String.sub p (String.length p - 8) 8 = "/refresh");
  Alcotest.(check (option string))
    "refresh token in query" (Some "R")
    (Uri.get_query_param req.url "token")

let test_cached_until_expiry () =
  let requests = ref [] in
  let token = make_jwt ~exp_epoch:(int_of_float (Unix.gettimeofday ()) + 600) in
  let transport : Http_transport.t =
   fun req ->
    requests := req :: !requests;
    { status = 200; body = body token }
  in
  let auth = Auth.make ~transport ~cfg:(make_cfg ()) in
  let _ = Auth.current auth in
  let _ = Auth.current auth in
  let _ = Auth.current auth in
  Alcotest.(check int) "subsequent calls reuse cache" 1 (List.length !requests)

(* A JWT whose [exp] is already in the past must not be cached — proves
   the [exp] claim is actually decoded rather than a blanket TTL. *)
let test_refresh_when_expired () =
  let requests = ref [] in
  let transport : Http_transport.t =
   fun req ->
    requests := req :: !requests;
    let now = int_of_float (Unix.gettimeofday ()) in
    let exp = if List.length !requests = 1 then now - 1 else now + 600 in
    { status = 200; body = body (make_jwt ~exp_epoch:exp) }
  in
  let auth = Auth.make ~transport ~cfg:(make_cfg ()) in
  let _ = Auth.current auth in
  let _ = Auth.current auth in
  Alcotest.(check int) "expired token triggers re-auth" 2 (List.length !requests)

let tests =
  [
    ("first call POSTs /refresh", `Quick, test_first_call_posts_refresh);
    ("cached until expiry", `Quick, test_cached_until_expiry);
    ("refresh when JWT expired", `Quick, test_refresh_when_expired);
  ]
