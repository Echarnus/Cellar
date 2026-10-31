// swift-tools-version: 6.2
import PackageDescription

/// Approachable Concurrency (WWDC25 268): nonisolated async functions run on the caller's actor
/// (SE-0461), and a conformance can take its type's isolation (SE-0470). Every target has it.
let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI modules start on the main actor (SE-0466): a view, a store or a window controller is
/// main-actor code unless it says otherwise.
let mainActorByDefault: [SwiftSetting] = approachable + [.defaultIsolation(MainActor.self)]

/// The app shell: the two executables and the tests. The libraries are local packages under
/// `Packages/`, each with its own `Package.swift`, so a layer can only import what its package
/// declares — an illegal import is a compile error, not a review comment (#133):
///
///     CellarDomain   ← nothing
///     CellarKit      ← CellarDomain           (+ CellarInfrastructure, the adapters)
///     CellarUI       ← CellarDomain, CellarKit
///     cellar, CellarApp (here) ← all of them; only their entry points import CellarInfrastructure
let package = Package(
    name: "Cellar",
    // The newest macOS every M1 Mac can run (Apple's compatibility list, issue #113). Spelled as a
    // string so the manifest does not need a tools version that knows `.v27`.
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "cellar", targets: ["cellar"]),
        .executable(name: "CellarApp", targets: ["CellarApp"]),
    ],
    dependencies: [
        .package(path: "Packages/CellarDomain"),
        .package(path: "Packages/CellarKit"),
        .package(path: "Packages/CellarUI"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // The app's self-updater. Pinned exactly: it installs code on the player's Mac, so a new
        // version is a deliberate bump, not whatever resolved last.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Thin CLI over CellarKit.
        .executableTarget(
            name: "cellar",
            dependencies: [
                .product(name: "CellarKit", package: "CellarKit"),
                .product(name: "CellarDomain", package: "CellarDomain"),
                .product(name: "CellarInfrastructure", package: "CellarKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "src/cellar",
            swiftSettings: approachable
        ),

        // A native SwiftUI "Steam-like" front-end over the same CellarKit core. Drives the
        // `cellar` CLI as a subprocess for actions, so it reuses every tested path.
        .executableTarget(
            name: "CellarApp",
            dependencies: [
                .product(name: "CellarKit", package: "CellarKit"),
                .product(name: "CellarDomain", package: "CellarDomain"),
                .product(name: "CellarInfrastructure", package: "CellarKit"),
                .product(name: "CellarUI", package: "CellarUI"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "src/CellarApp",
            // Inside Cellar.app the framework sits in Contents/Frameworks (Scripts/bundle-app.sh);
            // SwiftPM's own @loader_path rpath still finds it beside the binary in .build.
            swiftSettings: mainActorByDefault,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),

        .testTarget(
            name: "CellarKitTests",
            dependencies: [
                .product(name: "CellarKit", package: "CellarKit"),
                .product(name: "CellarDomain", package: "CellarDomain"),
                .product(name: "CellarInfrastructure", package: "CellarKit"),
            ],
            path: "tests/CellarKitTests"
        ),

        // Renders the marks offscreen and measures them. Needs the profile database and the golden
        // images on disk, so it is handed the repo root rather than guessing from #filePath.
        .testTarget(
            name: "CellarUITests",
            dependencies: [
                .product(name: "CellarUI", package: "CellarUI"),
                .product(name: "CellarKit", package: "CellarKit"),
                .product(name: "CellarDomain", package: "CellarDomain"),
            ],
            path: "tests/CellarUITests"
        ),

        // Tiered integration tests. Tier A is hermetic; tiers B and C install a real runner, build
        // a real Wine prefix and run a real Windows executable, and are opt-in behind environment
        // variables so the default run stays fast and CI stays green. See docs/TESTING.md.
        .testTarget(
            name: "CellarIntegrationTests",
            dependencies: [
                .product(name: "CellarKit", package: "CellarKit"),
                .product(name: "CellarDomain", package: "CellarDomain"),
                .product(name: "CellarInfrastructure", package: "CellarKit"),
            ],
            path: "tests/CellarIntegrationTests"
        ),
    ],
    // Every target, tests included, is checked in Swift 6 mode: data-race safety is a compile error,
    // not a warning (#77). Each local package says the same in its own manifest.
    swiftLanguageModes: [.v6]
)
