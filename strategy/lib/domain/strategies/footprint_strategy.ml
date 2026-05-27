open Core

module type S = sig
  type state
  type params

  val name : string
  val default_params : params
  val init : params -> state
  val on_footprint : state -> Instrument.t -> Footprint_bar.t -> state * Signal.t
end

type t = E : (module S with type state = 's and type params = 'p) * 's -> t

let make (type s p) (module M : S with type state = s and type params = p) (params : p) :
    t =
  E ((module M), M.init params)

let default (type s p) (module M : S with type state = s and type params = p) : t =
  E ((module M), M.init M.default_params)

let on_footprint (E ((module M), st)) instrument bar =
  let st', sig_ = M.on_footprint st instrument bar in
  (E ((module M), st'), sig_)

let name (E ((module M), _)) = M.name
