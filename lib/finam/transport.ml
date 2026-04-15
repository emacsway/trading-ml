(** HTTP transport abstraction.
    The concrete implementation (cohttp-eio + TLS, plain HTTP, or a test
    fake) is injected into [Rest.make]; the REST layer never sees flows. *)

type headers = (string * string) list

type request = {
  meth : [ `GET | `POST | `DELETE ];
  url : Uri.t;
  headers : headers;
  body : string option;
}

type response = {
  status : int;
  body : string;
}

type t = request -> response

(** Bypass-switch used in tests. *)
let fake (responder : request -> response) : t = responder
