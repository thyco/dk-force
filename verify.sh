#!/usr/bin/env bash
# DK Force verification gate.  Run from the repository root.
set -uo pipefail
cd "$(dirname "$0")"
ADDON=DKForce
FAIL=0
say() { printf '%-46s %s\n' "$1" "$2"; }

# 1. Syntax-check every addon Lua file (vendored Libs are never edited).
while IFS= read -r f; do
  if out=$(luac -p "$f" 2>&1); then
    say "syntax  $f" "OK"
  else
    say "syntax  $f" "FAIL"; echo "$out"; FAIL=1
  fi
done < <(find "$ADDON" -name '*.lua' -not -path "$ADDON/Libs/*" | sort)

# TOC must exist before checks 2 and 3 can read it.
[ -f "$ADDON/$ADDON.toc" ] || { say "toc file" "MISSING"; FAIL=1; }

# 2. Every file the TOC lists must exist.
if [ -f "$ADDON/$ADDON.toc" ]; then
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in ''|'#'*) continue;; esac
    if [ ! -f "$ADDON/$line" ]; then say "toc lists missing file" "$line"; FAIL=1; fi
  done < "$ADDON/$ADDON.toc"
fi

# 3. Every addon Lua file must be listed in the TOC (an unlisted file never loads).
if [ -f "$ADDON/$ADDON.toc" ]; then
  while IFS= read -r f; do
    rel=${f#"$ADDON/"}
    if ! grep -qxF "$rel" "$ADDON/$ADDON.toc"; then say "file not listed in toc" "$rel"; FAIL=1; fi
  done < <(find "$ADDON" -name '*.lua' -not -path "$ADDON/Libs/*" | sort)
fi

# 4. No stale DKAssist identifiers outside Libs and attribution lines.
stale=$(grep -rniE "dkassist|dk assist" "$ADDON" --include='*.lua' --include='*.toc' 2>/dev/null \
        | grep -v "/Libs/" | grep -vi "originally\|attribution\|derived from\|ZachoWOW")
if [ -n "$stale" ]; then say "stale DKAssist identifiers (any case)" "FAIL"; echo "$stale"; FAIL=1
else say "stale DKAssist identifiers (any case)" "OK"; fi

# 5. Dangling references to deleted symbols.
if [ -f removed-symbols.txt ]; then
  dangling=0
  while IFS= read -r sym; do
    sym=$(printf '%s' "$sym" | tr -d '\r')
    case "$sym" in ''|'#'*) continue;; esac
    hits=$(grep -rn --include='*.lua' -w -- "$sym" "$ADDON" 2>/dev/null | grep -v "/Libs/")
    if [ -n "$hits" ]; then say "dangling symbol" "$sym"; echo "$hits"; dangling=1; FAIL=1; fi
  done < removed-symbols.txt
  [ $dangling -eq 0 ] && say "removed-symbol check" "OK"
fi

# 6. No stale slash-command strings.
stalecmd=$(grep -rn "/dka\b\|/dkassist\b" "$ADDON" --include='*.lua' 2>/dev/null | grep -v "/Libs/")
if [ -n "$stalecmd" ]; then say "stale slash command" "FAIL"; echo "$stalecmd"; FAIL=1
else say "stale slash command" "OK"; fi

# 7. Behavioural specs.  Each one slices a real subsystem out of the shipped
#    source and runs it under desktop Lua with the WoW API stubbed, so it
#    exercises the code that ships rather than a retyped copy.  This started as
#    an md5 over the Stand In Death and Decay subsystem, which only proved the
#    bytes had not changed: every intentional edit failed it and was resolved by
#    re-blessing the hash, so it was a speed bump rather than a defence, and it
#    could not survive the code moving to another file.
#
#    Every tests/*_spec.lua runs, so adding a spec needs no edit here.  The D&D
#    one is named explicitly because it is the feature this project exists to
#    preserve: its absence is a failure, not an empty glob.  Each assertion in
#    both specs was proven to fail against a deliberately broken copy before the
#    spec was trusted.
if [ ! -f tests/dnd_missing_spec.lua ]; then
  say "DnD behaviour spec" "MISSING"; FAIL=1
elif ! command -v lua >/dev/null 2>&1; then
  say "behaviour specs" "SKIP (no lua)"
else
  for spec in tests/*_spec.lua; do
    if out=$(lua "$spec" 2>&1); then
      # The spec prints its own pass line, including its assertion count.
      printf '%s\n' "$out"
    else
      say "spec  $(basename "$spec")" "FAIL"; echo "$out"; FAIL=1
    fi
  done
fi

# 8. No leaked globals.  A local that was deleted but still referenced compiles
#    fine and reads as a global at runtime -- invisible to grep and to luac -p.
#    Dumping each chunk's _ENV accesses catches exactly that.  known-globals.txt
#    is the allowlist, generated from reviewed code; a NEW name here is either a
#    genuine new API call (add it deliberately) or a leak (fix the code).
if ! command -v luac >/dev/null 2>&1; then
  say "leaked globals" "SKIP (no luac)"
elif [ "$(luac -p -l "$ADDON/Core.lua" 2>/dev/null | grep -c '_ENV')" -eq 0 ]; then
  # NB: grep -c, not grep -q.  This script runs under `set -o pipefail`, and
  # grep -q exits on its first match, SIGPIPEing luac and failing the pipeline
  # even though the probe succeeded -- which silently disabled this check.
  say "leaked globals" "SKIP (luac too old to list _ENV)"
elif [ ! -f known-globals.txt ]; then
  say "leaked globals" "SKIP (no known-globals.txt)"
else
  leaked=""
  for f in "$ADDON"/*.lua; do
    while IFS= read -r g; do
      [ -z "$g" ] && continue
      grep -qxF "$g" known-globals.txt || leaked="$leaked\n  $(basename "$f"): $g"
    done < <(luac -p -l "$f" 2>/dev/null | grep -oE '_ENV "[A-Za-z_][A-Za-z0-9_]*"' | sed 's/_ENV "//; s/"//' | sort -u)
  done
  if [ -n "$leaked" ]; then
    say "leaked globals" "FAIL"; printf "%b\n" "$leaked"; FAIL=1
  else
    say "no leaked globals" "OK"
  fi
fi

if [ $FAIL -eq 0 ]; then say "RESULT" "PASS"; else say "RESULT" "FAIL"; fi
exit $FAIL
