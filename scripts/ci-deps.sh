#!/usr/bin/env bash
# Install build deps for the current OS. Run from repo root on a CI runner.
set -euo pipefail

case "${1:-$(uname -s)}" in
  Linux|linux|ubuntu*)
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      ecl \
      libgc-dev \
      libgmp-dev \
      locales \
      postgresql-16 \
      postgresql-server-dev-16
    ;;
  Darwin|darwin|macOS|macos*)
    brew list ecl >/dev/null 2>&1 || brew install ecl
    brew list postgresql@16 >/dev/null 2>&1 || brew install postgresql@16
    if [[ -n "${GITHUB_PATH:-}" ]]; then
      echo "$(brew --prefix postgresql@16)/bin" >> "$GITHUB_PATH"
      echo "$(brew --prefix ecl)/bin" >> "$GITHUB_PATH"
    else
      export PATH="$(brew --prefix postgresql@16)/bin:$(brew --prefix ecl)/bin:$PATH"
    fi
    ;;
  MINGW*|MSYS*|Windows|windows*)
    echo "Windows: MSYS2 no longer packages ECL. Use scripts/ci-windows-msvc.ps1 (EDB + ECL 24.5.10)." >&2
    ;;
  *)
    echo "unknown os: $1" >&2
    exit 1
    ;;
esac
