# Testing

## 1) Upstream neon native tests (required)
```bash
./scripts/build-neon-macos.sh
./scripts/test-neon-native.sh
```

Notes:
- This runs `make -C test check` in the out-of-tree build directory.
- On macOS, Homebrew `coreutils` is required so `date -d` works in `test/makekeys`.
- `scripts/test-neon-native.sh` automatically syncs `server.key` for out-of-tree tests and cleans it up after run.

## 2) Swift tests (required)
```bash
swift test
```

## iOS artifact build (integration)
```bash
IOS_SDK=iphonesimulator \
OPENSSL_IOS_ROOT=/path/to/ios-sim-openssl \
./scripts/build-neon-ios.sh
```

## 3) Enforce submodule integrity
```bash
./scripts/check-neon-submodule-clean.sh
```
