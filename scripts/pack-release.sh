#!/usr/bin/env bash
# Stage an install into dist/plecl-$VERSION-$PLATFORM.{tar.gz,zip}
# Usage: pack-release.sh linux-x86_64
# windows-x86_64-msvc flattens the live MSVC/EDB install (pg_config).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PLATFORM=${1:?platform id (linux-x86_64|macos-arm64|macos-x86_64|windows-x86_64|windows-x86_64-msvc)}
VERSION=${VERSION:-$(sed -n "s/.*default_version *= *['\"]\\([^'\"]*\\)['\"].*/\\1/p" plecl.control)}
NAME="plecl-${VERSION}-${PLATFORM}"
STAGE=$(mktemp -d)
DEST="$STAGE/root"
DIST="$ROOT/dist"
mkdir -p "$DEST" "$DIST"

win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

if [[ "$PLATFORM" == *msvc* ]]; then
  if ! command -v pg_config >/dev/null 2>&1; then
    echo "pg_config is required to pack windows-*-msvc (install first)" >&2
    exit 1
  fi
  PKGLIB=$(win_path "$(pg_config --pkglibdir)")
  SHARE=$(win_path "$(pg_config --sharedir)")
  mkdir -p "$DEST/lib" "$DEST/share/extension"
  cp -a "$PKGLIB/plecl.dll" "$DEST/lib/"
  cp -a "$PKGLIB/plecl.lisp" "$PKGLIB/inspect.lisp" "$PKGLIB/blob.lisp" "$PKGLIB/asdf.lisp" "$DEST/lib/"
  cp -a "$PKGLIB/ecl.dll" "$DEST/lib/"
  [[ -f "$PKGLIB/help.doc" ]] && cp -a "$PKGLIB/help.doc" "$DEST/lib/"
  [[ -d "$PKGLIB/encodings" ]] && cp -a "$PKGLIB/encodings" "$DEST/lib/"
  cp -a "$SHARE/extension/plecl.control" "$SHARE"/extension/plecl--*.sql "$DEST/share/extension/"
else
  make DESTDIR="$DEST" with_llvm=no install
fi

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
  if [[ "$PLATFORM" == *msvc* ]]; then
    copy_one "$ST/lib/" -name 'ecl.dll'
    enc=$(find "$DEST" -type d -name encodings | head -n 1)
    if [[ -n "$enc" ]]; then
      cp -a "$enc" "$ST/lib/"
    fi
    helpdoc=$(find "$DEST" -name help.doc | head -n 1)
    if [[ -n "$helpdoc" ]]; then
      cp -a "$helpdoc" "$ST/lib/"
    fi
  fi
else
  copy_one "$ST/lib/" \( -name 'plecl.so' -o -name 'plecl.dylib' \)
fi
copy_one "$ST/share/extension/" -name 'plecl.control'
copy_one "$ST/share/extension/" -name 'plecl--*.sql'
copy_one "$ST/lib/" -name 'plecl.lisp'
copy_one "$ST/lib/" -name 'inspect.lisp'
copy_one "$ST/lib/" -name 'blob.lisp'
copy_one "$ST/lib/" -name 'asdf.lisp'
fasc=$(find "$DEST" -name asdf.fasc | head -n 1)
if [[ -n "$fasc" ]]; then
  cp -a "$fasc" "$ST/lib/"
fi
cp -a LICENSE README.md "$ST/"
printf '%s\n' "$VERSION" "$PLATFORM" > "$ST/VERSION"

if [[ "$PLATFORM" == windows-* ]]; then
  if command -v zip >/dev/null 2>&1; then
    (cd "$DIST" && zip -r "${NAME}.zip" "$NAME")
  else
    (cd "$DIST" && tar -a -cf "${NAME}.zip" "$NAME")
  fi
  echo "$DIST/${NAME}.zip"
else
  tar -C "$DIST" -czf "$DIST/${NAME}.tar.gz" "$NAME"
  echo "$DIST/${NAME}.tar.gz"
fi
