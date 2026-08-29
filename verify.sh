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

# 7. The Stand In Death and Decay subsystem must stay byte-identical.
#    This is the feature the whole project exists to preserve.  The window is
#    found by logical bounds -- the banner rule through the `end)` that closes
#    dndMissingWatcher -- so it stays exact as surrounding code moves.
#    Task 9 made two deliberate, named edits (dropping BloodDnDGlowActiveOn and
#    the `shared` yield parameter) and this hash was updated with them, after the
#    diff was inspected and confirmed to contain only those two edits.
DND_EXPECTED_MD5=1d26116eaa80b74e05f7c4a1cae69a60
if command -v md5 >/dev/null 2>&1; then _md5() { md5 -q; }
else _md5() { md5sum | cut -d" " -f1; }; fi
dndstart=$(grep -n "^-- Death and Decay Buff Reminder (Blood)$" "$ADDON/Core.lua" 2>/dev/null | cut -d: -f1)
dndend=$(awk -v s="$dndstart" 'NR>s && /^end\)$/ {print NR; exit}' "$ADDON/Core.lua" 2>/dev/null)
if [ -z "$dndstart" ] || [ -z "$dndend" ]; then
  say "DnD subsystem bounds" "NOT FOUND"; FAIL=1
else
  dndmd5=$(sed -n "$((dndstart-1)),${dndend}p" "$ADDON/Core.lua" | _md5)
  if [ "$dndmd5" = "$DND_EXPECTED_MD5" ]; then
    say "DnD subsystem byte-identical" "OK"
  else
    say "DnD subsystem byte-identical" "FAIL (got $dndmd5)"
    say "  -> Stand In Death and Decay was modified." "This is the protected feature."
    FAIL=1
  fi
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
