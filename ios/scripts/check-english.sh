#!/bin/bash
#
# check-english.sh — fails if Danish user-facing text survives in the app.
#
# BetterLectio was a Danish app for Danish gymnasiums. BetterW4 serves an international IB college
# in Norway where every W4 page is in English, so a leftover "Skema" or "Fravær" is not a cosmetic
# nit — it is a string the user cannot read.
#
# Two detectors, because one is not enough:
#   1. Scandinavian characters (æøåÆØÅ) — catches "Fravær", "Læser", "Årgang".
#   2. A word list — catches the Danish words that contain none of those characters, which is most
#      of the tab bar: Skema, Beskeder, Lektier, Opgaver, Mere, Indstillinger.
#
# Run from anywhere:  ios/scripts/check-english.sh
# Exit 0 = clean, 1 = Danish remains.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/BetterW4"

FILES=()
while IFS= read -r line; do FILES+=("$line"); done < <(ls "$APP"/*.swift 2>/dev/null)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "check-english: no Swift files found under $APP — wrong directory?"
  exit 1
fi

# Whole words only, case-insensitive. Chosen to avoid English collisions:
# "Mere" is a real English word, so it is matched only as a standalone quoted UI string elsewhere;
# it is deliberately NOT in this list to avoid false positives on prose.
# Deliberately excludes Danish words that are also ordinary English words, because a gate that
# cries wolf gets switched off. "Sender" is the obvious one — W4's mailer grid genuinely has a
# sender column, and flagging every "from"/"sender" label taught the gate to be ignored.
# Likewise "Hold" (Danish: a class group) and "Mere" (Danish: more) are skipped: the Scandinavian
# character check and code review cover what is left.
DANISH_WORDS='Skema|Beskeder|Lektier|Opgaver|Indstillinger|Fravaer|Karakterer|Log ind|Log ud|Indlaeser|Afbryd|Gemmer|Modtager|Afsender|Vedhaeftede|Ugedag|Aflyst|Aendret|Laerer|Naeste|Forrige|Tilbage|Vaelg|Soeg|Aktiviteter|Klassekammerater'

status=0
total=0

# --- 1. Scandinavian characters -------------------------------------------------------------
scand=$(grep -nE '[æøåÆØÅ]' "${FILES[@]}" 2>/dev/null \
  | awk -F: '{ line=$0; sub(/^[^:]*:[0-9]*:/, "", line); if (line !~ /^[[:space:]]*(\/\/|\*|\/\*)/) print }' \
  || true)

if [ -n "$scand" ]; then
  count=$(printf '%s\n' "$scand" | wc -l | tr -d ' ')
  total=$((total + count))
  status=1
  echo ""
  echo "FAIL  Scandinavian characters in code  ($count lines)"
  echo "      Danish text the user cannot read. Translate to English."
  printf '%s\n' "$scand" | sed "s|$ROOT/||" | sed 's/^/      /' | head -25
  [ "$count" -gt 25 ] && echo "      … and $((count - 25)) more"
fi

# --- 2. Danish words without special characters ----------------------------------------------
words=$(grep -nEi "\"[^\"]*\b($DANISH_WORDS)\b" "${FILES[@]}" 2>/dev/null \
  | awk -F: '{ line=$0; sub(/^[^:]*:[0-9]*:/, "", line); if (line !~ /^[[:space:]]*(\/\/|\*|\/\*)/) print }' \
  || true)

if [ -n "$words" ]; then
  count=$(printf '%s\n' "$words" | wc -l | tr -d ' ')
  total=$((total + count))
  status=1
  echo ""
  echo "FAIL  Danish words in string literals  ($count lines)"
  echo "      e.g. Skema -> Timetable, Beskeder -> Mail, Lektier/Opgaver -> Assessments,"
  echo "           Fravaer -> Absence, Karakterer -> Grades, Log ud -> Log out."
  printf '%s\n' "$words" | sed "s|$ROOT/||" | sed 's/^/      /' | head -25
  [ "$count" -gt 25 ] && echo "      … and $((count - 25)) more"
fi

echo ""
if [ $status -eq 0 ]; then
  echo "check-english: clean — ${#FILES[@]} Swift files, no Danish user-facing text."
else
  echo "check-english: $total line(s) still contain Danish."
fi

exit $status
