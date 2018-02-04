#!/usr/bin/env bash

set -e

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

cd "$BASEDIR"

cleanup() {
	rm -rf ./fatpacker.trace ./packlists ./fatlib
}
trap "cleanup" INT TERM EXIT

# Make sure fatpacker finds the local libs
PERL5OPT="-I$(pwd)/local/lib/perl5"
export PERL5OPT

# Respect carton-installed fatpacker and perlstrip
PATH="$(pwd)/local/bin:$PATH"
export PATH

# Preparations: Tracing
fatpack trace --use=common::sense ./igor.pl
fatpack packlists-for $(cat fatpacker.trace) > packlists
fatpack tree $(cat packlists)

# Run perlstrip
find ./fatlib -type f -exec perlstrip --size {} \;

# Pack the script
fatpack file ./igor.pl > ./igor.packed.pl
# Bugfix: common::sense is in ARCHLIB
sed -i 's!x86_64-linux-thread-multi/!!g' ./igor.packed.pl

chmod u+x ./igor.packed.pl
