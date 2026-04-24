# How to work with Gospel specifications

End-to-end walkthrough: run the existing Gospel type-checker over the
annotated domain `.mli` files, add a new specification, and understand
what the current build actually proves (and what it doesn't).

[Gospel][gospel] is a tool-agnostic specification language for OCaml.
You write contracts — `requires`, `ensures`, `raises`, `modifies` — in
`(*@ … *)` comments inside `.mli` signatures, and downstream tools
consume them: `gospel check` validates them syntactically and
name-resolves them against the OCaml types; [Ortac][ortac] translates
them into runtime assertions for property tests; [Cameleer][cameleer]
maps a subset into [Why3][why3] for proof. This repo currently uses
only `gospel check`; Ortac/Why3 integration is on the roadmap.

[gospel]: https://github.com/ocaml-gospel/gospel
[ortac]: https://github.com/ocaml-gospel/ortac
[cameleer]: https://github.com/ocaml-gospel/cameleer
[why3]: https://why3.lri.fr/

## What the build checks today

```bash
dune build @gospel
```

The `@gospel` alias walks every `.mli` under `lib/domain/` and runs
`gospel check` on files that carry at least one `(*@ … *)` block.
Exit status is `0` iff every annotation parses and every name inside
it resolves. A malformed annotation — misspelled exception, typo in a
field reference, reference to a non-existent function — fails the
alias with a pointed diagnostic.

Current specs (as of Phase 0 wiring):

| File                              | Spec kind                                                  |
| --------------------------------- | ---------------------------------------------------------- |
| `lib/domain/core/decimal.mli`     | `div` raises `Division_by_zero`                            |
| `lib/domain/core/candle.mli`      | `make` invariants: `low ≤ open,close ≤ high`, `volume ≥ 0` |
| `lib/domain/engine/portfolio.mli` | `empty` postconditions; `fill` raises `Invalid_argument`   |

These are minimal by design. Phase 0 wiring is about *not letting
specs rot silently* — every time `dune build @gospel` runs, broken
annotations surface immediately. Expanding the catalogue is Phase 1.

## Add a new specification

1. Pick an `.mli` file under `lib/domain/`.
2. Below the `val` declaration, open a `(*@ … *)` block:

   ```ocaml
   val div : t -> t -> t
   (** Raises [Division_by_zero] if [b] is [zero]. *)
   (*@ r = div a b
       raises Division_by_zero -> true *)
   ```

   Shape: `<result_var> = <fn_name> <arg_vars>` on the first line,
   then `requires` / `ensures` / `raises` clauses. See the
   [Gospel language reference][gospel-lang] for the full grammar.

3. `dune build @gospel` — the new file is picked up automatically
   (selection is driven by the presence of `(*@` in the source, not
   by a list).

4. If the check fails with
   `Error: Symbol Foo not found in scope`, you likely referenced an
   OCaml identifier Gospel can't resolve — either a typo, or one of
   the known limitations below.

[gospel-lang]: https://ocaml-gospel.github.io/gospel/language/syntax

## Known limitations of Gospel 0.3.1

Hit these in practice while wiring Phase 0 — expect to hit them again
when writing new specs.

### `Format.formatter` crashes the type-checker

Gospel's internal stdlib stub doesn't include `Format`. Any `.mli`
referencing `Format.formatter` crashes `gospel check` with
`File "src/typing.ml", line 721, … Assertion failed`.

**Mitigation.** The `@gospel` alias skips `.mli` files that have no
`(*@` annotation, so `pp`-only modules (`Ticker`, `Mic`, `Isin`,
`Board`, `Instrument`) don't block the build today. If you want to
annotate one of them, first move the `pp` signature into a separate
`<module>_pp.mli` or accept a workaround (e.g. phantom type stub).

### No understanding of dune-wrapped libraries

By default, a dune `(library (name core))` implicitly wraps
submodules as `Core.Decimal`, `Core.Instrument`, etc. Gospel doesn't
know this convention — pointing `--load-path` at `lib/domain/core/`
finds the sibling `.mli` files but not their wrapped namespace.
`engine/portfolio.mli` writes `Core.Instrument.t` in its types; a
plain `gospel check` fails with `Error: No module with name Core`.

**Mitigation.** `tools/gospel_wrap.sh` generates a synthesized
`core.mli` wrapper: one `module <Cap> : sig … end` block per
submodule, in topological order, with `Format.formatter` lines
stripped. The rule in `lib/domain/engine/gospel_stubs/dune` runs it
before `gospel check`, and the engine alias passes
`-L gospel_stubs` so the synthesized file is on the load path.

### No `module rec`

Gospel rejects mutually recursive module declarations
(`module rec A … and B …`), so the wrapper generator topologically
sorts modules by intra-library references. Circular references
between two modules in the same library would currently be
unsupported; we don't have any today.

### Dune ignores subdirs starting with `_`

A generated-artifact subdir named `_gospel_stubs/` would be invisible
to dune — its internal rules wouldn't register. The synthesized
wrapper therefore lives in `gospel_stubs/` (no leading underscore).

## How the wiring fits together

```
dune-project
  └── (depends … (gospel (>= 0.3.1)))

lib/domain/core/dune
  └── (rule (alias gospel) …)        ; checks *.mli with (*@ annotations

lib/domain/engine/dune
  └── (rule (alias gospel) …)        ; depends on gospel_stubs/core.mli

lib/domain/engine/gospel_stubs/dune
  └── (rule (target core.mli) …)     ; invokes tools/gospel_wrap.sh

tools/gospel_wrap.sh
  └── python3 generator: topo-sort + strip Format.formatter
```

Adding a new library under `lib/domain/` that wants specs:

- Copy the `core/dune` pattern if the specs reference only
  intra-library types.
- Copy the `engine/` pattern (including a `gospel_stubs/` subdir) if
  specs reference types from another dune-wrapped library.

## Roadmap

Phase 0 — **done**: `dune build @gospel` enforces that annotations
parse and name-resolve.

Phase 1 — **next**: expand specifications across the domain core.
Good candidates in decreasing order of payoff:

- `Portfolio.try_reserve` / `try_release` — the reservation
  invariants (non-negative `available_cash`, monotone `reservations`
  list) are the safety-critical logic.
- `Instrument.equal` / `compare` — total order laws, symmetry.
- `Decimal.add` / `mul` / `div` — associativity / commutativity
  where they hold; rescaling bounds for `mul`.

Phase 2 — **Ortac runtime checks**: `opam install ortac-qcheck-stm`,
generate runtime-checked wrappers from the Gospel annotations,
integrate with the existing QCheck property tests. The aggregates
(`Portfolio`) are the natural first target — they are state
machines, which `qcheck-stm` is built for.

Phase 3 — **Cameleer/Why3 proofs** for pure numeric code. Requires
an SMT solver stack (Alt-Ergo, Z3, CVC) and currently needs
Cameleer pinned from git (not in opam). Targets: `Decimal`
arithmetic laws, indicator invariants on fixed-length windows.

## Troubleshooting

**`Error: Symbol X not found in scope`** — check the Gospel
[symbols-in-scope][gospel-scope] reference. Most common causes: typo
in exception name, reference to a record field that doesn't exist on
the result type, use of an OCaml identifier that Gospel doesn't
model (e.g. anything from `Format`, `Printf`, `Buffer`).

**`gospel: internal error, … Assertion failed`** — almost always
the `Format.formatter` crash above. Confirm with
`grep -n Format.formatter <file>`; if present, either remove the
annotation from that file or move the `pp` signature out.

**`Error: No module with name Core`** — `gospel check` ran without
the synthesized wrapper on its load path. If you're invoking gospel
by hand (not via `dune build @gospel`), point it at the wrapper:

```bash
dune build lib/domain/engine/gospel_stubs/core.mli
gospel check -L lib/domain/engine/gospel_stubs -L lib/domain/engine \
  lib/domain/engine/portfolio.mli
```

**The alias passes but I expected it to fail** — confirm your
annotation actually contains `(*@` (not e.g. `(*&` or `(*! `); the
file selector is a literal grep. Confirm the file lives under
`lib/domain/`; files elsewhere are not in the alias's scope.

[gospel-scope]: https://ocaml-gospel.github.io/gospel/language/scope
