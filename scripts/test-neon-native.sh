#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/neon/macos-build"
BUILD_TEST_DIR="$BUILD_DIR/test"
SOURCE_TEST_DIR="$ROOT_DIR/Vendor/neon/test"
SOURCE_SERVER_KEY="$SOURCE_TEST_DIR/server.key"
BUILD_SERVER_KEY="$BUILD_TEST_DIR/server.key"
SERVER_KEY_BACKUP=""

if [[ ! -f "$BUILD_DIR/Makefile" ]]; then
  echo "neon build directory is missing; run scripts/build-neon-macos.sh first" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$SERVER_KEY_BACKUP" && -f "$SERVER_KEY_BACKUP" ]]; then
    cp -f "$SERVER_KEY_BACKUP" "$SOURCE_SERVER_KEY"
    rm -f "$SERVER_KEY_BACKUP"
  else
    rm -f "$SOURCE_SERVER_KEY"
  fi
}
trap cleanup EXIT

if [[ -x "/opt/homebrew/opt/openssl@3/bin/openssl" ]]; then
  export OPENSSL="/opt/homebrew/opt/openssl@3/bin/openssl"
elif [[ -x "/usr/local/opt/openssl@3/bin/openssl" ]]; then
  export OPENSSL="/usr/local/opt/openssl@3/bin/openssl"
fi

if [[ -d "/opt/homebrew/opt/coreutils/libexec/gnubin" ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
elif [[ -d "/usr/local/opt/coreutils/libexec/gnubin" ]]; then
  export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
fi

if [[ ! -f "$BUILD_SERVER_KEY" ]]; then
  # ca-stamp can be stale while server.key is missing; force regeneration.
  rm -f "$BUILD_TEST_DIR/ca-stamp"
  make -C "$BUILD_TEST_DIR" ca-stamp
fi

if [[ ! -f "$BUILD_SERVER_KEY" ]]; then
  echo "missing $BUILD_SERVER_KEY after ca-stamp generation" >&2
  exit 1
fi

if [[ -f "$SOURCE_SERVER_KEY" ]]; then
  SERVER_KEY_BACKUP="$(mktemp "$ROOT_DIR/.build/neon/server.key.backup.XXXXXX")"
  cp -f "$SOURCE_SERVER_KEY" "$SERVER_KEY_BACKUP"
fi

cp -f "$BUILD_SERVER_KEY" "$SOURCE_SERVER_KEY"

make -C "$BUILD_TEST_DIR" check
