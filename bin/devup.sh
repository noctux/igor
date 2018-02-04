#!/usr/bin/env bash

set -e

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

# Start the docker container
docker run --volume="${BASEDIR}:/home/user/igor:ro"           \
           --tty                                              \
           --interactive                                      \
           --rm                                               \
           --workdir=/home/user/igor                          \
           --env=PERL5OPT="-I/home/user/igor/local/lib/perl5" \
           igor:archlinux                                     \
           /usr/bin/bash
