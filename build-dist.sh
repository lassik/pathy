#!/bin/sh -
set -eu
cd "$(dirname "$0")"
[ -n "${PROGVERSION:-}" ] || { echo "PROGVERSION must be set"; exit 1; }
stem="pathy-$PROGVERSION"
tarfile="$stem.tar.gz"
[ ! -e "$stem" ] || { echo "$stem already exists"; exit 1; }
mkdir -m 0700 -- "$stem"
cp -Rp -- $(git ls-files) "$stem/"
find "$stem/" -print0 | xargs -0 chmod u+rw,g+r-w,o+r-w
tar -czf "$tarfile.new" -- "$stem"
mv -f -- "$tarfile.new" "$tarfile"
rm -rf -- "$stem"
sync
echo "Created $tarfile"
