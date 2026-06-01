(** End-to-end tests — start the real HTTP server in-process, drive it
    over TCP with a real HTTP client, assert on the response. Slow,
    so kept in a separate executable from [unit]. *)

let () = Alcotest.run "trading-e2e" [ ("footprint_stream", Footprint_stream_test.tests) ]
