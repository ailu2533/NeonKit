# Build Neon on macOS

## Prerequisites
- Xcode command line tools
- Homebrew `openssl@3`
- Homebrew `coreutils` (for GNU `date` compatibility in `neon` test scripts)

## Build
```bash
./scripts/build-neon-macos.sh
```

Notes:
- `MACOS_MIN_VERSION` is supported (default `13.0`).
- If `Vendor/neon/configure` is missing, the script runs `autogen.sh` automatically.
- Install step intentionally skips manpage targets (not shipped in the git tag source snapshot).

Artifacts are produced under:
- `.build/neon/macos/lib/libneon.a`
- `.build/neon/macos/include/ne_*.h`

## Swift build
```bash
swift build
```
