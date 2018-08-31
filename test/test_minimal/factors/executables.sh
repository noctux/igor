#!/usr/bin/env sh

echo "executables = ["

IFS=':';
for i in $PATH; do
	test -d "$i" && find "$i" -maxdepth 1 -executable -type f -exec basename {} \;;
done | sort -u | sed 's/^/\t"/g;s/$/",/g'

echo "]"
