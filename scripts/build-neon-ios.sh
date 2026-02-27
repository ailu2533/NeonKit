#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEON_SRC_DIR="$ROOT_DIR/Vendor/neon"
IOS_BUILD_ROOT="$ROOT_DIR/.build/neon/ios"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-16.0}"
IOS_SDK="${IOS_SDK:-iphonesimulator}"

# Required:
# - OPENSSL_IOS_ROOT: prefix containing include/ + lib/ for selected IOS_SDK
#
# Optional:
# - IOS_ARCHS: arch list to build (default: iphoneos=arm64, iphonesimulator="arm64 x86_64")
# - OPENSSL_IOS_SIM_X86_64_ROOT: separate OpenSSL prefix for x86_64 simulator
# - EXPAT_IOS_ROOT: optional override prefix containing include/ + lib/ for expat
# - EXPAT_IOS_SIM_X86_64_ROOT: optional expat override prefix for simulator x86_64
: "${OPENSSL_IOS_ROOT:?Set OPENSSL_IOS_ROOT to prebuilt OpenSSL prefix for selected IOS_SDK}"

mkdir -p "$IOS_BUILD_ROOT"

if [[ ! -d "$NEON_SRC_DIR" ]]; then
  echo "missing submodule at $NEON_SRC_DIR" >&2
  exit 1
fi

if [[ ! -x "$NEON_SRC_DIR/configure" ]]; then
  echo "configure script not found, generating with autogen.sh"
  (cd "$NEON_SRC_DIR" && ./autogen.sh)
fi

BUILD_TRIPLET="$("$NEON_SRC_DIR/config.guess")"

resolve_openssl_include_flags() {
  local openssl_root="$1"
  local compat_include_dir="$2"

  if [[ -d "$openssl_root/include/openssl" ]]; then
    echo "-I$openssl_root/include"
    return 0
  fi

  if [[ -d "$openssl_root/include/OpenSSL" ]]; then
    # Compatibility for prefixes that ship uppercase include/OpenSSL paths.
    mkdir -p "$compat_include_dir"
    ln -sfn "$openssl_root/include/OpenSSL" "$compat_include_dir/openssl"
    echo "-I$openssl_root/include -I$compat_include_dir"
    return 0
  fi

  echo "missing OpenSSL headers under $openssl_root/include (expected openssl/ or OpenSSL/)" >&2
  return 1
}

build_one() {
  local arch="$1"
  local host="$2"
  local openssl_root="$3"
  local expat_root="$4"
  local sdk="$IOS_SDK"
  local build_dir="$IOS_BUILD_ROOT/build-$sdk-$arch"
  local prefix_dir="$IOS_BUILD_ROOT/prefix-$sdk-$arch"
  local sysroot
  local min_flag
  local include_flags
  local library_flags
  local openssl_include_flags

  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  mkdir -p "$build_dir"

  pushd "$build_dir" >/dev/null

  export CC="$(xcrun --sdk "$sdk" -f clang)"
  export AR="$(xcrun --sdk "$sdk" -f ar)"
  export RANLIB="$(xcrun --sdk "$sdk" -f ranlib)"
  export PKG_CONFIG=false

  if [[ "$sdk" == "iphoneos" ]]; then
    min_flag="-miphoneos-version-min=$IOS_MIN_VERSION"
  else
    min_flag="-mios-simulator-version-min=$IOS_MIN_VERSION"
  fi

  openssl_include_flags="$(resolve_openssl_include_flags "$openssl_root" "$build_dir/openssl-include-compat")"
  include_flags="$openssl_include_flags"
  library_flags="-L$openssl_root/lib"

  if [[ -n "$expat_root" ]]; then
    include_flags="$include_flags -I$expat_root/include"
    library_flags="$library_flags -L$expat_root/lib"
  fi

  export CFLAGS="-arch $arch -isysroot $sysroot $min_flag $include_flags"
  export CPPFLAGS="$CFLAGS"
  export LDFLAGS="-arch $arch -isysroot $sysroot $min_flag $library_flags"

  "$NEON_SRC_DIR/configure" \
    --build="$BUILD_TRIPLET" \
    --host="$host" \
    --disable-shared \
    --enable-static \
    --with-ssl=openssl \
    --without-gssapi \
    --prefix="$prefix_dir"

  make -j"$(sysctl -n hw.ncpu)"
  # Keep install scope narrow; source snapshot does not include generated manpages.
  make install-lib install-headers install-config

  popd >/dev/null
}

if [[ "$IOS_SDK" != "iphoneos" && "$IOS_SDK" != "iphonesimulator" ]]; then
  echo "IOS_SDK must be iphoneos or iphonesimulator" >&2
  exit 1
fi

if [[ -z "${IOS_ARCHS:-}" ]]; then
  if [[ "$IOS_SDK" == "iphoneos" ]]; then
    IOS_ARCHS="arm64"
  else
    IOS_ARCHS="arm64 x86_64"
  fi
fi

unique_paths() {
  printf "%s\n" "$@" | awk 'NF && !seen[$0]++'
}

declare -a neon_libs
declare -a ssl_libs
declare -a crypto_libs
declare -a source_headers

for arch in $IOS_ARCHS; do
  openssl_root="$OPENSSL_IOS_ROOT"
  expat_root="${EXPAT_IOS_ROOT:-}"
  host="aarch64-apple-ios"

  if [[ "$arch" == "x86_64" ]]; then
    host="x86_64-apple-ios"
    if [[ -n "${OPENSSL_IOS_SIM_X86_64_ROOT:-}" ]]; then
      openssl_root="$OPENSSL_IOS_SIM_X86_64_ROOT"
    fi
    if [[ -n "${EXPAT_IOS_SIM_X86_64_ROOT:-}" ]]; then
      expat_root="$EXPAT_IOS_SIM_X86_64_ROOT"
    fi
  fi

  build_one "$arch" "$host" "$openssl_root" "$expat_root"

  prefix="$IOS_BUILD_ROOT/prefix-$IOS_SDK-$arch"
  neon_libs+=("$prefix/lib/libneon.a")
  ssl_libs+=("$openssl_root/lib/libssl.a")
  crypto_libs+=("$openssl_root/lib/libcrypto.a")
  source_headers+=("$prefix/include")
done

OUT_LIB_DIR="$IOS_BUILD_ROOT/lib"
OUT_INCLUDE_DIR="$IOS_BUILD_ROOT/include"

mkdir -p "$OUT_LIB_DIR" "$OUT_INCLUDE_DIR"

neon_libs_unique=()
while IFS= read -r lib; do
  neon_libs_unique+=("$lib")
done < <(unique_paths "${neon_libs[@]}")

ssl_libs_unique=()
while IFS= read -r lib; do
  ssl_libs_unique+=("$lib")
done < <(unique_paths "${ssl_libs[@]}")

crypto_libs_unique=()
while IFS= read -r lib; do
  crypto_libs_unique+=("$lib")
done < <(unique_paths "${crypto_libs[@]}")

lipo -create "${neon_libs_unique[@]}" -output "$OUT_LIB_DIR/libneon.a"
lipo -create "${ssl_libs_unique[@]}" -output "$OUT_LIB_DIR/libssl.a"
lipo -create "${crypto_libs_unique[@]}" -output "$OUT_LIB_DIR/libcrypto.a"

if compgen -G "${source_headers[0]}/neon/ne_*.h" >/dev/null; then
  cp -f "${source_headers[0]}"/neon/ne_*.h "$OUT_INCLUDE_DIR/"
else
  cp -f "${source_headers[0]}"/ne_*.h "$OUT_INCLUDE_DIR/"
fi

echo "Built iOS static libs for $IOS_SDK ($IOS_ARCHS):"
echo "  $OUT_LIB_DIR/libneon.a"
echo "  $OUT_LIB_DIR/libssl.a"
echo "  $OUT_LIB_DIR/libcrypto.a"
echo "  (expat uses iOS SDK system libexpat.tbd)"
