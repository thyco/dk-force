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
#    This is the feature the whole project exists to preserve.  Tasks 1-8 must
#    not alter one byte of it; Task 9 makes two deliberate, named edits and
#    updates DND_EXPECTED_MD5 below in the same change.
DND_EXPECTED_MD5=da89d08b0c2294db1a61db1f473b25f4
dndstart=$(grep -n "^-- Death and Decay Buff Reminder (Blood)$" "$ADDON/Core.lua" 2>/dev/null | cut -d: -f1)
if [ -z "$dndstart" ]; then
  say "DnD subsystem banner" "MISSING"; FAIL=1
else
  dndfrom=$((dndstart-1)); dndto=$((dndfrom+175))
  if command -v md5 >/dev/null 2>&1; then _md5() { md5 -q; }
  else _md5() { md5sum | cut -d" " -f1; }; fi
  dndmd5=$(sed -n "${dndfrom},${dndto}p" "$ADDON/Core.lua" | _md5)
  if [ "$dndmd5" = "$DND_EXPECTED_MD5" ]; then
    say "DnD subsystem byte-identical" "OK"
  else
    say "DnD subsystem byte-identical" "FAIL (got $dndmd5)"
    say "  -> Stand In Death and Decay was modified." "This is the protected feature."
    FAIL=1
  fi
fi

if [ $FAIL -eq 0 ]; then say "RESULT" "PASS"; else say "RESULT" "FAIL"; fi
exit $FAIL
