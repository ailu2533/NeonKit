// swift-tools-version: 5.10

import PackageDescription

let xcframeworkPath = "Artifacts/NeonNative.xcframework"

let neonLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("z", .when(platforms: [.macOS])),
    .linkedLibrary("z", .when(platforms: [.iOS])),
    .linkedLibrary("expat", .when(platforms: [.macOS])),
    .linkedLibrary("expat", .when(platforms: [.iOS])),
]

let targets: [Target] = [
    .binaryTarget(
        name: "NeonNative",
        path: xcframeworkPath
    ),
    .systemLibrary(
        name: "CNeon",
        path: "Sources/CNeon"
    ),
    .target(
        name: "CNeonShim",
        dependencies: ["CNeon", "NeonNative"],
        path: "Sources/CNeonShim",
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("../CNeon/include"),
        ],
        linkerSettings: neonLinkerSettings
    ),
    .target(
        name: "NeonRaw",
        dependencies: ["CNeon", "CNeonShim", "NeonNative"],
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
