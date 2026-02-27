# Build NeonNative XCFramework

Use this when you want consumers to add only the Git URL and use `NeonKit` directly.

## Goal
Produce and commit:
- `Artifacts/NeonNative.xcframework`

`Package.swift` automatically switches to binary mode when this path exists.

## Required env vars
- `OPENSSL_IOS_DEVICE_ROOT`: OpenSSL prefix for `iphoneos`
- `OPENSSL_IOS_SIM_ROOT`: OpenSSL prefix for `iphonesimulator`

## Optional env vars
- `OPENSSL_MACOS_ROOT`: OpenSSL prefix for macOS (`openssl@3`), auto-detected if omitted
- `OPENSSL_IOS_SIM_X86_64_ROOT`: separate simulator x86_64 OpenSSL prefix
- `EXPAT_IOS_ROOT`, `EXPAT_IOS_SIM_X86_64_ROOT`: expat override prefixes
- `MACOS_MIN_VERSION`: default `13.0`
- `IOS_MIN_VERSION`: default `16.0`
- `OUTPUT_XCFRAMEWORK`: output path (default `Artifacts/NeonNative.xcframework`)

## Example (krzyzanowskim/OpenSSL)
```bash
git clone https://github.com/krzyzanowskim/OpenSSL.git /tmp/OpenSSL

OPENSSL_IOS_DEVICE_ROOT=/tmp/OpenSSL/iphoneos \
OPENSSL_IOS_SIM_ROOT=/tmp/OpenSSL/iphonesimulator \
./scripts/build-neon-xcframework.sh
```

## Validate
```bash
swift build
swift test
```

Note:
- The generated `.a` archives are not byte-for-byte deterministic across rebuilds on Apple toolchains.
- CI validates XCFramework layout/architectures via `scripts/verify-neon-xcframework.sh` instead of `git diff` on binaries.

## Publish for Git URL usage
1. Build `Artifacts/NeonNative.xcframework`.
2. Commit and push it with your package source.
3. Consumers add your repository URL in Xcode/SwiftPM and `import NeonKit`.
