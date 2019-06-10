#!/usr/bin/env bash

set -e

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

perl -MPod::Select -e "podselect('$BASEDIR/scripts/igor.pl')" > "$BASEDIR/README.pod"
