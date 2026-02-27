// swift-tools-version: 6.2

import PackageDescription
import Foundation

let xcframeworkPath = "Artifacts/NeonNative.xcframework"
let hasXCFramework = FileManager.default.fileExists(atPath: xcframeworkPath)

let sourceModeLibraryPaths = [
    "/opt/homebrew/opt/openssl@3/lib",
    "/usr/local/opt/openssl@3/lib",
    "/opt/homebrew/lib",
    "/usr/local/lib",
].filter { FileManager.default.fileExists(atPath: $0) }

let sourceModeLinkerSettingsBase: [LinkerSetting] = [
    .unsafeFlags(["-L", ".build/neon/macos/lib"], .when(platforms: [.macOS])),
    .unsafeFlags(["-L", ".build/neon/ios/lib"], .when(platforms: [.iOS])),
    .linkedLibrary("neon", .when(platforms: [.macOS])),
    .linkedLibrary("neon", .when(platforms: [.iOS])),
    .linkedLibrary("z", .when(platforms: [.macOS])),
    .linkedLibrary("z", .when(platforms: [.iOS])),
    .linkedLibrary("expat", .when(platforms: [.macOS])),
    .linkedLibrary("expat", .when(platforms: [.iOS])),
    .linkedLibrary("ssl", .when(platforms: [.macOS])),
    .linkedLibrary("ssl", .when(platforms: [.iOS])),
    .linkedLibrary("crypto", .when(platforms: [.macOS])),
    .linkedLibrary("crypto", .when(platforms: [.iOS])),
]

var sourceModeLinkerSettings = sourceModeLinkerSettingsBase
for path in sourceModeLibraryPaths {
    sourceModeLinkerSettings.insert(.unsafeFlags(["-L", path], .when(platforms: [.macOS])), at: 1)
}

let binaryModeLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("z", .when(platforms: [.macOS])),
    .linkedLibrary("z", .when(platforms: [.iOS])),
    .linkedLibrary("expat", .when(platforms: [.macOS])),
    .linkedLibrary("expat", .when(platforms: [.iOS])),
]

let neonLinkerSettings = hasXCFramework ? binaryModeLinkerSettings : sourceModeLinkerSettings

let cNeonShimDependencies: [Target.Dependency] = hasXCFramework
    ? ["CNeon", "NeonNative"]
    : ["CNeon"]

let neonRawDependencies: [Target.Dependency] = hasXCFramework
    ? ["CNeon", "CNeonShim", "NeonNative"]
    : ["CNeon", "CNeonShim"]

var targets: [Target] = []
if hasXCFramework {
    targets.append(
        .binaryTarget(
            name: "NeonNative",
            path: xcframeworkPath
        )
    )
}

targets += [
    .systemLibrary(
        name: "CNeon",
        path: "Sources/CNeon"
    ),
    .target(
        name: "CNeonShim",
        dependencies: cNeonShimDependencies,
        path: "Sources/CNeonShim",
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("../CNeon/include"),
        ],
        linkerSettings: neonLinkerSettings
    ),
    .target(
        name: "NeonRaw",
        dependencies: neonRawDependencies,
        linkerSettings: neonLinkerSettings
    ),
    .target(
        name: "NeonKit",
        dependencies: ["NeonRaw"]
    ),
    .testTarget(
        name: "NeonRawTests",
        dependencies: ["NeonRaw"]
    ),
    .testTarget(
        name: "NeonKitTests",
        dependencies: ["NeonKit"]
    ),
]

let package = Package(
    name: "NeonKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "NeonRaw", targets: ["NeonRaw"]),
        .library(name: "NeonKit", targets: ["NeonKit"]),
    ],
    targets: targets
)
