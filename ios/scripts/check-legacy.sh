#!/bin/bash
#
# check-legacy.sh — fails if any Lectio-era protocol, host or concept has crept back into the app.
#
# BetterW4 is a port of BetterLectio. The whole point of the port is that the app talks to
# w4.uwcrcn.no and nothing else, so a single surviving lectio.dk URL or ASP.NET postback is a
# porting bug, not a harmless leftover: it would send a W4 session cookie to a third party and
# hit a server that cannot answer it.
#
# The same applies one level up, in the model layer. Lectio served many gymnasiums, so it scoped
# everything by school; W4 is one college on one host. A `gymId` or a per-student `schoolName`
# would not break a request, but it would be a lie in a cache key and an identity — which is
# worse, because it is invisible until two students collide. And a `PORTSHIM` is by definition a
# symbol kept alive only until its caller was ported; the port is done, so a new one is dead
# Lectio shape being kept on life support.
#
# Run from anywhere:  ios/scripts/check-legacy.sh
# Exit 0 = clean, 1 = a banned pattern is present.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/BetterW4"
TESTS="$ROOT/BetterW4Tests"

# Pattern | human explanation
BANNED=(
  'lectio\.dk|a Lectio host — the app must only ever talk to w4.uwcrcn.no'
  '\.aspx|an ASP.NET page — W4 is Yii, its routes are index.php?r=...'
  '__VIEWSTATE|__EVENTVALIDATION|__doPostBack|an ASP.NET postback — W4 uses plain Yii form posts'
  'ASP\.NET_SessionId|a Lectio cookie — W4 has exactly one cookie, PHPSESSID'
  'autologinkeyV2|autologinkey|a Lectio autologin cookie — W4 has no such thing'
  'broker\.unilogin\.dk|UniLogin|MitID|Danish national login — W4 uses username + password + 2FA'
  'GetImage\.aspx|the Lectio avatar endpoint — W4 serves {uwc_id}_thumb.jpg'
  'gymId|a Lectio gymnasium id — Lectio served many schools so every URL and cache key carried one. W4 is one school on one host: the uwc id is the whole identity'
  'schoolName|a school display name on the model — there is one school, so a per-student name is a Lectio leftover. The sign-in copy uses AuthenticationService.collegeName'
)

# Matched *everywhere*, comments included. Everything above is a symbol that only counts as a bug
# when it survives in real code; each pattern below is a marker that only ever lives in a comment,
# so exempting comments would exempt the pattern entirely.
BANNED_IN_COMMENTS_TOO=(
  'PORTSHIM|a port shim — a symbol kept alive only until its caller was ported. Every caller is now gone or rewritten, so a new one means dead Lectio shape is being kept on life support'
)

# Swift source only. Fixtures under BetterW4Tests/Fixtures deliberately contain captured Lectio
# markup for regression tests, and the docs describe the port, so both are out of scope.
#
# Two test files are exempt, and only these two. They are the NEGATIVE tests: they must name a
# Lectio host or an ASP.NET token in order to assert that it is rejected. Exempting them is not a
# loophole — deleting their references would delete the proof that the rule is enforced:
#
#   W4HostGateTests.swift  builds a lectio.dk URL and asserts the HTTP client refuses to send it
#   W4FixtureTests.swift   asserts the captured W4 pages contain no ASP.NET postback machinery
#
# Everything else, in the app and in the tests, must be clean.
NEGATIVE_TESTS="W4HostGateTests.swift|W4FixtureTests.swift"

# The same idea one line at a time, for the case a whole-file exemption is far too blunt for: a
# DENY-LIST has to spell a banned name in order to refuse it. `W4Credentials.refusedNames` is that
# — it names the Lectio cookies so a stale Keychain blob cannot smuggle one back onto the wire —
# and exempting all of StudentModels.swift to allow it would exempt the core model file.
#
# So a single line may opt out with a trailing `// legacy-name:` marker plus a reason. It is
# deliberately verbose: it reads as a claim someone made on purpose, it shows up in a diff, and it
# cannot be applied to a whole file by accident. It does NOT apply to the comments-included
# patterns below — a PORTSHIM has no legitimate negative use.
LINE_EXEMPTION='// legacy-name:'

FILES=()
while IFS= read -r line; do
  case "$line" in
    *W4HostGateTests.swift|*W4FixtureTests.swift) continue ;;
  esac
  FILES+=("$line")
done < <(
  ls "$APP"/*.swift 2>/dev/null
  ls "$TESTS"/*.swift 2>/dev/null
)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "check-legacy: no Swift files found under $ROOT — wrong directory?"
  exit 1
fi

status=0
total=0

# Comment lines are exempt. "W4 is Yii, so there is no __VIEWSTATE here" is exactly the kind of
# note that stops someone re-introducing the thing, and a gate that forces you to delete your own
# explanation is a gate people learn to ignore. Executable code is what gets judged: a string
# literal, a URL, a symbol. Comments are stripped before matching, so a banned pattern only counts
# when it survives in real code.
strip_comments() {
  grep -vE '^[[:space:]]*(//|\*|/\*)' || true
}

for entry in "${BANNED[@]}"; do
  pattern="${entry%%|*}"
  explanation="${entry##*|}"

  hits=$(grep -nE "$pattern" "${FILES[@]}" 2>/dev/null \
    | awk -F: -v exempt="$LINE_EXEMPTION" '{
        line=$0; sub(/^[^:]*:[0-9]*:/, "", line)
        if (line ~ /^[[:space:]]*(\/\/|\*|\/\*)/) next
        if (index(line, exempt) > 0) next
        print
      }' \
    || true)

  if [ -n "$hits" ]; then
    count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    total=$((total + count))
    status=1
    echo ""
    echo "FAIL  $pattern  ($count $([ "$count" = 1 ] && echo hit || echo hits))"
    echo "      $explanation"
    printf '%s\n' "$hits" | sed "s|$ROOT/||" | sed 's/^/      /' | head -20
    if [ "$count" -gt 20 ]; then
      echo "      … and $((count - 20)) more"
    fi
  fi
done

for entry in "${BANNED_IN_COMMENTS_TOO[@]}"; do
  pattern="${entry%%|*}"
  explanation="${entry##*|}"

  hits=$(grep -nE "$pattern" "${FILES[@]}" 2>/dev/null || true)

  if [ -n "$hits" ]; then
    count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    total=$((total + count))
    status=1
    echo ""
    echo "FAIL  $pattern  ($count $([ "$count" = 1 ] && echo hit || echo hits))  [comments included]"
    echo "      $explanation"
    printf '%s\n' "$hits" | sed "s|$ROOT/||" | sed 's/^/      /' | head -20
    if [ "$count" -gt 20 ]; then
      echo "      … and $((count - 20)) more"
    fi
  fi
done

echo ""
if [ $status -eq 0 ]; then
  echo "check-legacy: clean — ${#FILES[@]} Swift files, no Lectio protocol, host or model concept."
  echo "              (negative tests exempt: ${NEGATIVE_TESTS//|/, })"
else
  echo "check-legacy: $total reference(s) to Lectio-era protocol or model concepts remain."
fi

exit $status
