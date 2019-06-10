#!/usr/bin/env bash

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

PERL5LIB="$PERL5LIB:$BASEDIR/local/lib/perl5"; export PERL5LIB
(
	cd "$BASEDIR"
	milla "$@"
)
