# Cross-BC wire contracts

Authoritative wire-format definitions for every type that crosses a
Bounded Context boundary on the bus or on the HTTP API. Each
contract is an [ATD](https://github.com/ahrefs/atd) source file
consumed at build time by `atdgen` to produce the typed OCaml
record and its JSON serialiser/deserialiser pair (`*_t.ml`,
`*_j.ml`).

## Layout

One subtree per BC, mirroring the application-layer split:

```
shared/contracts/<bc>/
├── commands/                    # CQRS commands accepted by the BC
├── queries/                     # CQRS query DTOs accepted by the BC
├── integration_events/          # IEs emitted by the BC
└── view_models/                 # Read-side projections of the BC's
                                 # domain entities (embedded in IEs
                                 # or returned by HTTP read endpoints)
```

A type that is consumed by multiple BCs — e.g. paper_broker and
broker both need a `submit_order_command` wire shape that the
saga can target uniformly — is **duplicated** in each consumer
BC's tree. Per the project's BC-independence rule, commands,
integration events and view models must not be imported across
BCs. The duplication is structural; a cross-BC contract test
(`shared/tests/contract/`) verifies byte-for-byte equivalence.

## Workflow

When the contract changes:

1. Edit the canonical `.atd` in each BC tree that owns a copy.
2. `dune build` regenerates `*_t.{ml,mli}` and `*_j.{ml,mli}` in
   the BCs that consume them; any breaking shape change becomes
   a compile error at the call site.
3. `dune runtest` exercises the cross-BC contract roundtrip
   tests; any silent wire divergence becomes a test failure.

Silent additive changes (a new optional field) do not surface
either as a compile error or as a contract-test failure unless
the new field is exercised in the test sample — every PR adding
an optional field must include a sample value populating it.

The CODEOWNERS for `shared/contracts/` covers maintainers of all
BCs that touch the contract: any PR editing a contract requires
explicit acknowledgement from each BC owner.
