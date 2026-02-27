#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/neon/xcframework"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/Artifacts}"
OUTPUT_XCFRAMEWORK="${OUTPUT_XCFRAMEWORK:-$OUTPUT_DIR/NeonNative.xcframework}"

# Required:
# - OPENSSL_IOS_DEVICE_ROOT: OpenSSL prefix for iphoneos
# - OPENSSL_IOS_SIM_ROOT: OpenSSL prefix for iphonesimulator
#
# Optional:
# - OPENSSL_MACOS_ROOT: OpenSSL prefix for macOS (auto-detected from Homebrew if omitted)
# - OPENSSL_IOS_SIM_X86_64_ROOT: alternate OpenSSL prefix for simulator x86_64
# - EXPAT_IOS_ROOT / EXPAT_IOS_SIM_X86_64_ROOT: override expat prefixes
# - MACOS_MIN_VERSION: macOS deployment target passed to macOS build script (default 13.0)
# - IOS_MIN_VERSION: iOS deployment target passed to iOS build script (default 16.0)
: "${OPENSSL_IOS_DEVICE_ROOT:?Set OPENSSL_IOS_DEVICE_ROOT to iOS device OpenSSL prefix}"
: "${OPENSSL_IOS_SIM_ROOT:?Set OPENSSL_IOS_SIM_ROOT to iOS simulator OpenSSL prefix}"

resolve_macos_openssl_root() {
  if [[ -n "${OPENSSL_MACOS_ROOT:-}" ]]; then
    echo "$OPENSSL_MACOS_ROOT"
    return 0
  fi

  if [[ -d "/opt/homebrew/opt/openssl@3" ]]; then
    echo "/opt/homebrew/opt/openssl@3"
    return 0
  fi

  if [[ -d "/usr/local/opt/openssl@3" ]]; then
    echo "/usr/local/opt/openssl@3"
    return 0
  fi

  echo "could not determine OPENSSL_MACOS_ROOT; set it explicitly" >&2
  return 1
}

ensure_library() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing required library: $path" >&2
    exit 1
  fi
}

combine_static_libs() {
  local output="$1"
  shift
  xcrun libtool -static -o "$output" "$@"
}

rm -rf "$WORK_DIR" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$WORK_DIR/macos" "$WORK_DIR/iphoneos" "$WORK_DIR/iphonesimulator" "$WORK_DIR/headers/Modules" "$OUTPUT_DIR"

OPENSSL_MACOS_ROOT="$(resolve_macos_openssl_root)"
OPENSSL_BIN="$OPENSSL_MACOS_ROOT/bin/openssl"
if [[ ! -x "$OPENSSL_BIN" ]]; then
  echo "missing OpenSSL binary at $OPENSSL_BIN" >&2
  exit 1
fi

# Build macOS static neon + headers.
OPENSSL_BIN="$OPENSSL_BIN" \
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}" \
"$ROOT_DIR/scripts/build-neon-macos.sh"

ensure_library "$ROOT_DIR/.build/neon/macos/lib/libneon.a"
ensure_library "$OPENSSL_MACOS_ROOT/lib/libssl.a"
ensure_library "$OPENSSL_MACOS_ROOT/lib/libcrypto.a"

combine_static_libs \
  "$WORK_DIR/macos/libneonnative.a" \
  "$ROOT_DIR/.build/neon/macos/lib/libneon.a" \
  "$OPENSSL_MACOS_ROOT/lib/libssl.a" \
  "$OPENSSL_MACOS_ROOT/lib/libcrypto.a"

# Build iOS device static libs and preserve outputs before simulator build overwrites shared output paths.
IOS_SDK=iphoneos \
OPENSSL_IOS_ROOT="$OPENSSL_IOS_DEVICE_ROOT" \
EXPAT_IOS_ROOT="${EXPAT_IOS_ROOT:-}" \
IOS_MIN_VERSION="${IOS_MIN_VERSION:-16.0}" \
"$ROOT_DIR/scripts/build-neon-ios.sh"

cp -f "$ROOT_DIR/.build/neon/ios/lib/libneon.a" "$WORK_DIR/iphoneos/libneon.a"
cp -f "$OPENSSL_IOS_DEVICE_ROOT/lib/libssl.a" "$WORK_DIR/iphoneos/libssl.a"
cp -f "$OPENSSL_IOS_DEVICE_ROOT/lib/libcrypto.a" "$WORK_DIR/iphoneos/libcrypto.a"

# Build iOS simulator static libs.
IOS_SDK=iphonesimulator \
OPENSSL_IOS_ROOT="$OPENSSL_IOS_SIM_ROOT" \
OPENSSL_IOS_SIM_X86_64_ROOT="${OPENSSL_IOS_SIM_X86_64_ROOT:-}" \
EXPAT_IOS_ROOT="${EXPAT_IOS_ROOT:-}" \
EXPAT_IOS_SIM_X86_64_ROOT="${EXPAT_IOS_SIM_X86_64_ROOT:-}" \
IOS_MIN_VERSION="${IOS_MIN_VERSION:-16.0}" \
"$ROOT_DIR/scripts/build-neon-ios.sh"

cp -f "$ROOT_DIR/.build/neon/ios/lib/libneon.a" "$WORK_DIR/iphonesimulator/libneon.a"
cp -f "$OPENSSL_IOS_SIM_ROOT/lib/libssl.a" "$WORK_DIR/iphonesimulator/libssl.a"
cp -f "$OPENSSL_IOS_SIM_ROOT/lib/libcrypto.a" "$WORK_DIR/iphonesimulator/libcrypto.a"

combine_static_libs \
  "$WORK_DIR/iphoneos/libneonnative.a" \
  "$WORK_DIR/iphoneos/libneon.a" \
  "$WORK_DIR/iphoneos/libssl.a" \
  "$WORK_DIR/iphoneos/libcrypto.a"

combine_static_libs \
  "$WORK_DIR/iphonesimulator/libneonnative.a" \
  "$WORK_DIR/iphonesimulator/libneon.a" \
  "$WORK_DIR/iphonesimulator/libssl.a" \
  "$WORK_DIR/iphonesimulator/libcrypto.a"

# Minimal module metadata for SwiftPM binary target import/link.
cat > "$WORK_DIR/headers/NeonNative.h" <<'HDR'
#ifndef NEON_NATIVE_H
#define NEON_NATIVE_H

/* Marker header for NeonNative binary target. */

#endif
HDR

cat > "$WORK_DIR/headers/Modules/module.modulemap" <<'MMAP'
module NeonNative {
    header "NeonNative.h"
    export *
}
MMAP

xcodebuild -create-xcframework \
  -library "$WORK_DIR/macos/libneonnative.a" -headers "$WORK_DIR/headers" \
  -library "$WORK_DIR/iphoneos/libneonnative.a" -headers "$WORK_DIR/headers" \
  -library "$WORK_DIR/iphonesimulator/libneonnative.a" -headers "$WORK_DIR/headers" \
  -output "$OUTPUT_XCFRAMEWORK"

echo "Created XCFramework: $OUTPUT_XCFRAMEWORK"
