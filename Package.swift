// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cellar", targets: ["cellar"]),
        .executable(name: "CellarApp", targets: ["CellarApp"]),
        .library(name: "CellarKit", targets: ["CellarKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Core engine: environment detection, bottles, runners, profiles.
        // The future SwiftUI app (Phase 3) imports this same library.
        .target(name: "CellarKit"),

        // Thin CLI over CellarKit.
        .executableTarget(
            name: "cellar",
            dependencies: [
                "CellarKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // Phase 3: a native SwiftUI "Steam-like" front-end over the same CellarKit core. Drives the
        // `cellar` CLI as a subprocess for actions, so it reuses every tested path.
        .executableTarget(name: "CellarApp", dependencies: ["CellarKit"]),
    ],
    // Pragmatic: a synchronous CLI doesn't need Swift 6 strict-concurrency overhead yet.
    swiftLanguageModes: [.v5]
)
