#!/usr/bin/env bash
# Generate a gospel-consumable wrapper .mli for a dune-wrapped OCaml library.
#
# Gospel (0.3.1) does not understand dune's implicit `Lib__Module` wrapping,
# so cross-library references like `Lib.Module.t` cannot be resolved by
# pointing `--load-path` at the library directory. This script produces a
# single <libname>.mli that inlines each submodule's signature as
#   module <Cap> : sig
#     <contents of <cap>.mli, with gospel-unsafe lines stripped>
#   end
# in topological order (gospel has no `module rec` support, so a module must
# appear before any other module that references it).
#
# Stripped: lines referring to Format.formatter (Format is absent from
# gospel's stdlib; any occurrence crashes the type-checker).
#
# Usage: gospel_wrap.sh <mli-files...>

set -eu

exec python3 - "$@" <<'PY'
import os
import re
import sys

files = sys.argv[1:]
modules = {}
for f in files:
    base = os.path.basename(f)
    if not base.endswith(".mli"):
        continue
    name = base[:-4]
    cap = name[0].upper() + name[1:]
    with open(f) as fh:
        body = fh.read()
    modules[cap] = (f, body)

mod_names = set(modules)
ref_re = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.[A-Za-z_]")
deps = {}
for cap, (_, body) in modules.items():
    code = re.sub(r"\(\*.*?\*\)", "", body, flags=re.DOTALL)
    refs = {m.group(1) for m in ref_re.finditer(code)}
    deps[cap] = (refs & mod_names) - {cap}

order = []
remaining = dict(deps)
while remaining:
    ready = sorted(m for m, d in remaining.items() if not d)
    if not ready:
        # cycle — emit rest alphabetically; gospel will surface the issue
        order.extend(sorted(remaining))
        break
    for m in ready:
        order.append(m)
        del remaining[m]
    for m, d in remaining.items():
        remaining[m] = d - set(ready)

format_re = re.compile(r"Format\.formatter")
for cap in order:
    _, body = modules[cap]
    print(f"module {cap} : sig")
    for line in body.splitlines():
        if format_re.search(line):
            continue
        print(line)
    print("end\n")
PY
