# Build Neon for iOS

`neon` is built externally (submodule source remains untouched).

If you want Git URL consumers to use the package without local build scripts, build and commit `Artifacts/NeonNative.xcframework` via `docs/build-xcframework.md`.

## Required env vars
- `OPENSSL_IOS_ROOT`: prefix containing `include/` and `lib/` for selected `IOS_SDK`
  - supports both `include/openssl` and `include/OpenSSL`

## Optional env vars
- `IOS_SDK`: `iphoneos` or `iphonesimulator` (default `iphonesimulator`)
- `IOS_ARCHS`: architecture list for selected SDK
- `OPENSSL_IOS_SIM_X86_64_ROOT`: separate OpenSSL prefix for simulator `x86_64` when needed
- `EXPAT_IOS_ROOT`: optional override prefix for expat (`include/` + `lib/`)
- `EXPAT_IOS_SIM_X86_64_ROOT`: optional expat override prefix for simulator `x86_64`
- `IOS_MIN_VERSION`: deployment target (default `16.0`)

## Build command (static libs for current SDK)
```bash
IOS_SDK=iphonesimulator \
OPENSSL_IOS_ROOT=/path/to/ios-sim-openssl \
./scripts/build-neon-ios.sh
```

## Using `krzyzanowskim/OpenSSL`
After cloning https://github.com/krzyzanowskim/OpenSSL.git, use the platform folder as the prefix:

```bash
# Simulator
IOS_SDK=iphonesimulator \
OPENSSL_IOS_ROOT=/path/to/OpenSSL/iphonesimulator \
./scripts/build-neon-ios.sh

# Device
IOS_SDK=iphoneos \
OPENSSL_IOS_ROOT=/path/to/OpenSSL/iphoneos \
./scripts/build-neon-ios.sh
```

If you need `x86_64` simulator with a separate prefix:

```bash
IOS_SDK=iphonesimulator \
OPENSSL_IOS_ROOT=/path/to/OpenSSL/iphonesimulator \
OPENSSL_IOS_SIM_X86_64_ROOT=/path/to/x86_64/openssl-prefix \
./scripts/build-neon-ios.sh
```

Output:
- `.build/neon/ios/lib/libneon.a`
- `.build/neon/ios/lib/libssl.a`
- `.build/neon/ios/lib/libcrypto.a`
- `.build/neon/ios/include/ne_*.h`

## SwiftPM integration
- `Package.swift` links iOS builds from `.build/neon/ios/lib`.
- Build the matching SDK slice before building that destination with SwiftPM/Xcode.
- By default expat resolves from iOS SDK system library: `libexpat.tbd`.
- Only set `EXPAT_IOS_ROOT` when you need to force a custom expat build.
