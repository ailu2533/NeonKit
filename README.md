# NeonKit

Swift wrapper for `neon` (WebDAV client C library), with:
- `NeonRaw`: low-level wrapper close to C API
- `NeonKit`: higher-level actor/async API

This package is distributed in **binary-only mode** via:
- `Artifacts/NeonNative.xcframework`

`neon` is managed as a git submodule at `Vendor/neon` (do not modify upstream source directly).

## Upgrade `neon` (Submodule)

Example: upgrade to `0.37.0`.

1. Update submodule to target version:

```bash
git submodule update --init --recursive
git -C Vendor/neon fetch --tags
git -C Vendor/neon checkout 0.37.0
```

2. Sync exported `neon` headers used by `CNeon`:

```bash
find Sources/CNeon/include -name 'ne_*.h' -delete
cp -f Vendor/neon/src/ne_*.h Sources/CNeon/include/
```

3. Rebuild binary artifact (required for Git URL direct consumption):

```bash
OPENSSL_IOS_DEVICE_ROOT=/path/to/OpenSSL/iphoneos \
OPENSSL_IOS_SIM_ROOT=/path/to/OpenSSL/iphonesimulator \
./scripts/build-neon-xcframework.sh
```

4. Run validation:

```bash
./scripts/build-neon-macos.sh
./scripts/test-neon-native.sh
swift test
./scripts/check-neon-submodule-clean.sh
```

5. Commit:

```bash
git add Vendor/neon Sources/CNeon/include Artifacts/NeonNative.xcframework
git commit -m "chore: bump neon to 0.37.0"
```

## Notes

- `Vendor/neon` should be updated as gitlink only (submodule pointer).
- After each `neon` bump, rebuild and commit `Artifacts/NeonNative.xcframework`; otherwise Git URL consumers will not get updated binaries.
- More build details: `docs/build-xcframework.md`, `docs/build-macos.md`, `docs/build-ios.md`.
