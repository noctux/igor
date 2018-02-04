#!/usr/bin/env bash

set -e

BASEDIR="$(dirname "$0")/.."
BASEDIR="$(readlink -f "$BASEDIR")"

IMAGE="${1:?Please specify a image to use}"
TARARCHIVE="${2:?Please specify a path to write the home to}"

TARARCHIVE="$(readlink -f "$TARARCHIVE")"

cd "$BASEDIR"

FATPACKED="./igor.packed.pl"

# Ensure that the fatpacked script is available
if [[ ! -f "$FATPACKED" ]]; then
	./bin/fatpack.sh
fi

# Start the docker container
CONTAINERID="$(docker run -t -d "$IMAGE")"
echo "Running in container: $CONTAINERID"

cleanup() {
	echo "Cleaning up"
	docker stop "$CONTAINERID"
	docker rm "$CONTAINERID"
}
trap "cleanup" INT TERM EXIT

# Copy the fatpacked script, config and dummy repository
CONFIGID="1"
echo "COPY igor and config"
docker cp "$FATPACKED" "$CONTAINERID":/home/user/igor.pl
docker cp "./test/config${CONFIGID}.toml" "$CONTAINERID":/home/user/config.toml
docker cp "./test/repo${CONFIGID}" "$CONTAINERID":/home/user/repo
echo "COPY complete"

# Now run the test
echo "Running IGOR"
docker exec --workdir="/home/user" "$CONTAINERID" ./igor.pl --config ./config.toml apply --task computer
echo "IGOR run complete"
echo "Compressing filesystem"
docker exec --workdir="/home/user" "$CONTAINERID" tar --mtime=@0 --sort=name -cvf /tmp/archive.tar /home/user
echo "Done compressing filesystem"
echo "Copying artifact"
docker cp "$CONTAINERID":/tmp/archive.tar "$TARARCHIVE"
echo "Done compressing filesystem"
