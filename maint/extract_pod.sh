#!/usr/bin/env bash

set -euo pipefail

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

TMPFILE="$(mktemp)"
trap 'rm -f -- "$TMPFILE"' EXIT

perl -MPod::Select -e "podselect('$BASEDIR/scripts/igor.pl')" > "$TMPFILE"
pod2markdown "$TMPFILE" > "$BASEDIR/README.md"
