#!/usr/bin/env bash
# Stage PGXS install into dist/plecl-$VERSION-$PLATFORM.{tar.gz,zip}
# Usage: pack-release.sh linux-x86_64
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PLATFORM=${1:?platform id (linux-x86_64|macos-arm64|macos-x86_64|windows-x86_64)}
VERSION=${VERSION:-$(sed -n "s/.*default_version *= *['\"]\\([^'\"]*\\)['\"].*/\\1/p" plecl.control)}
NAME="plecl-${VERSION}-${PLATFORM}"
STAGE=$(mktemp -d)
DEST="$STAGE/root"
DIST="$ROOT/dist"
mkdir -p "$DEST" "$DIST"

make DESTDIR="$DEST" install

ST="$DIST/$NAME"
rm -rf "$ST"
mkdir -p "$ST/lib" "$ST/share/extension"

copy_one() {
  local dest=$1
  shift
  local f
  f=$(find "$DEST" "$@" | head -n 1)
  if [[ -z "$f" ]]; then
    echo "missing: $*" >&2
    find "$DEST" -type f | head -50 >&2
    exit 1
  fi
  cp -a "$f" "$dest"
}

if [[ "$PLATFORM" == windows-* ]]; then
  copy_one "$ST/lib/" -name 'plecl.dll'
else
  copy_one "$ST/lib/" \( -name 'plecl.so' -o -name 'plecl.dylib' \)
fi
copy_one "$ST/share/extension/" -name 'plecl.control'
copy_one "$ST/share/extension/" -name 'plecl--*.sql'
copy_one "$ST/lib/" -name 'plecl.lisp'
copy_one "$ST/lib/" -name 'inspect.lisp'
copy_one "$ST/lib/" -name 'blob.lisp'
copy_one "$ST/lib/" -name 'asdf.lisp'
cp -a LICENSE README.md "$ST/"
printf '%s\n' "$VERSION" "$PLATFORM" > "$ST/VERSION"

if [[ "$PLATFORM" == windows-* ]]; then
  (cd "$DIST" && zip -r "${NAME}.zip" "$NAME")
  echo "$DIST/${NAME}.zip"
else
  tar -C "$DIST" -czf "$DIST/${NAME}.tar.gz" "$NAME"
  echo "$DIST/${NAME}.tar.gz"
fi
