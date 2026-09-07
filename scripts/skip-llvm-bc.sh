#!/bin/sh
# PGXS bitcode: $(COMPILE.c.bc) [clang flags] -o $@ $<
# PGDG sets with_llvm=yes; we do not ship JIT bitcode.
out=
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      out=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  : > "$out"
fi
