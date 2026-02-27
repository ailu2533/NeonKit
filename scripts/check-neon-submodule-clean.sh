#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="$ROOT_DIR/Vendor/neon"

if [[ ! -d "$SUBMODULE_DIR/.git" && ! -f "$SUBMODULE_DIR/.git" ]]; then
  echo "Vendor/neon is not initialized" >&2
  exit 1
fi

if [[ -n "$(git -C "$SUBMODULE_DIR" status --porcelain)" ]]; then
  echo "Vendor/neon contains local modifications; this is not allowed" >&2
  git -C "$SUBMODULE_DIR" status --short
  exit 1
fi

echo "Vendor/neon is clean"
