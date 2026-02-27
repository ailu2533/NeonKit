#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEON_SRC_DIR="$ROOT_DIR/Vendor/neon"
BUILD_DIR="$ROOT_DIR/.build/neon/macos-build"
PREFIX_DIR="$ROOT_DIR/.build/neon/macos"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}"

ensure_autotools() {
  local missing=()

  command -v autoconf >/dev/null 2>&1 || missing+=("autoconf")
  command -v aclocal >/dev/null 2>&1 || missing+=("automake (aclocal)")
  command -v autoheader >/dev/null 2>&1 || missing+=("autoheader")
  if ! command -v libtoolize >/dev/null 2>&1 && ! command -v glibtoolize >/dev/null 2>&1; then
    missing+=("libtool (libtoolize/glibtoolize)")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing autotools for generating configure:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "install with: brew install autoconf automake libtool" >&2
    exit 1
  fi
}

if [[ ! -d "$NEON_SRC_DIR" ]]; then
  echo "missing submodule at $NEON_SRC_DIR" >&2
  exit 1
fi

if [[ ! -x "$NEON_SRC_DIR/configure" ]]; then
  ensure_autotools
  echo "configure script not found, generating with autogen.sh"
  (cd "$NEON_SRC_DIR" && ./autogen.sh)
fi

if [[ -x "/opt/homebrew/opt/openssl@3/bin/openssl" ]]; then
  OPENSSL_BIN_DEFAULT="/opt/homebrew/opt/openssl@3/bin/openssl"
elif [[ -x "/usr/local/opt/openssl@3/bin/openssl" ]]; then
  OPENSSL_BIN_DEFAULT="/usr/local/opt/openssl@3/bin/openssl"
else
  OPENSSL_BIN_DEFAULT=""
fi

OPENSSL_BIN="${OPENSSL_BIN:-$OPENSSL_BIN_DEFAULT}"
if [[ -z "$OPENSSL_BIN" || ! -x "$OPENSSL_BIN" ]]; then
  echo "OpenSSL binary not found. Set OPENSSL_BIN to openssl@3 executable." >&2
  exit 1
fi

OPENSSL_PREFIX="$(cd "$(dirname "$OPENSSL_BIN")/.." && pwd)"
MACOS_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_CC="$(xcrun --sdk macosx -f clang)"
COMMON_FLAGS="-isysroot $MACOS_SYSROOT -mmacosx-version-min=$MACOS_MIN_VERSION"

if [[ -d "/opt/homebrew/opt/coreutils/libexec/gnubin" ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
elif [[ -d "/usr/local/opt/coreutils/libexec/gnubin" ]]; then
  export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
fi

mkdir -p "$BUILD_DIR" "$PREFIX_DIR/lib" "$PREFIX_DIR/include" "$PREFIX_DIR/lib/pkgconfig"

pushd "$BUILD_DIR" >/dev/null

"$NEON_SRC_DIR/configure" \
  --disable-shared \
  --enable-static \
  --with-ssl=openssl \
  --without-gssapi \
  --prefix="$PREFIX_DIR" \
  CC="$MACOS_CC" \
  CPPFLAGS="$COMMON_FLAGS -I$OPENSSL_PREFIX/include" \
  CFLAGS="$COMMON_FLAGS" \
  LDFLAGS="$COMMON_FLAGS -L$OPENSSL_PREFIX/lib" \
  OPENSSL="$OPENSSL_BIN"

make -j"$(sysctl -n hw.ncpu)"
# 0.36.0 git tag does not ship generated manpages, so avoid install-docs target.
make install-lib install-headers install-config

cp -f "$BUILD_DIR/src/.libs/libneon.a" "$PREFIX_DIR/lib/libneon.a"
cp -f "$NEON_SRC_DIR/src"/ne_*.h "$PREFIX_DIR/include/"

cat > "$PREFIX_DIR/lib/pkgconfig/neon.pc" <<PC
prefix=$PREFIX_DIR
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: neon
Description: HTTP and WebDAV client library
Version: 0.36.0
Libs: -L\${libdir} -lneon -lz -lexpat -lssl -lcrypto
Cflags: -I\${includedir}
PC

popd >/dev/null

echo "neon built at: $PREFIX_DIR"
