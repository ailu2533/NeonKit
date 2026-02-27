#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK_PATH="${1:-$ROOT_DIR/Artifacts/NeonNative.xcframework}"

if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
  echo "missing xcframework: $XCFRAMEWORK_PATH" >&2
  exit 1
fi

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing file: $path" >&2
    exit 1
  fi
}

expect_archs() {
  local lib_path="$1"
  shift
  local -a expected_archs=("$@")
  local -a actual_archs=()
  read -r -a actual_archs <<<"$(xcrun lipo -archs "$lib_path")"

  if [[ "${#actual_archs[@]}" -ne "${#expected_archs[@]}" ]]; then
    echo "unexpected architectures for $lib_path" >&2
    echo "  expected: ${expected_archs[*]}" >&2
    echo "  actual:   ${actual_archs[*]}" >&2
    exit 1
  fi

  for arch in "${expected_archs[@]}"; do
    local found=0
    for actual in "${actual_archs[@]}"; do
      if [[ "$actual" == "$arch" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo "unexpected architectures for $lib_path" >&2
      echo "  expected: ${expected_archs[*]}" >&2
      echo "  actual:   ${actual_archs[*]}" >&2
      exit 1
    fi
  done
}

for slice in macos-arm64 ios-arm64 ios-arm64_x86_64-simulator; do
  require_file "$XCFRAMEWORK_PATH/$slice/libneonnative.a"
  require_file "$XCFRAMEWORK_PATH/$slice/Headers/NeonNative.h"
done

expect_archs "$XCFRAMEWORK_PATH/macos-arm64/libneonnative.a" arm64
expect_archs "$XCFRAMEWORK_PATH/ios-arm64/libneonnative.a" arm64
expect_archs "$XCFRAMEWORK_PATH/ios-arm64_x86_64-simulator/libneonnative.a" arm64 x86_64

require_file "$XCFRAMEWORK_PATH/Info.plist"

echo "XCFramework layout and architectures verified: $XCFRAMEWORK_PATH"
