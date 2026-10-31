// swift-tools-version: 6.2
import PackageDescription

/// Approachable Concurrency (WWDC25 268): nonisolated async functions run on the caller's actor
/// (SE-0461), and a conformance can take its type's isolation (SE-0470). Every target has it.
let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI modules start on the main actor (SE-0466): a view, a store or a window controller is
/// main-actor code unless it says otherwise. CellarKit stays nonisolated, as a library should.
let mainActorByDefault: [SwiftSetting] = approachable + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Cellar",
    // The newest macOS every M1 Mac can run (Apple's compatibility list, issue #113). Spelled as a
    // string so the manifest does not need a tools version that knows `.v27`.
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "cellar", targets: ["cellar"]),
        .executable(name: "CellarApp", targets: ["CellarApp"]),
        .library(name: "CellarKit", targets: ["CellarKit"]),
        .library(name: "CellarDomain", targets: ["CellarDomain"]),
        .library(name: "CellarInfrastructure", targets: ["CellarInfrastructure"]),
        .library(name: "CellarUI", targets: ["CellarUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // The app's self-updater. Pinned exactly: it installs code on the player's Mac, so a new
        // version is a deliberate bump, not whatever resolved last.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // The domain: pure types and policies — the stores' table of facts, launch stages, install
        // phases, the events a command reports. Foundation value types only, no I/O, so it is the
        // first target in Swift 6 language mode (docs/APP-ARCHITECTURE.md, step 10). Nothing here
        // may import CellarKit; the compiler is what keeps it that way.
        .target(name: "CellarDomain", path: "src/CellarDomain", swiftSettings: approachable),

        // Core engine: environment detection, bottles, runners, profiles, the use cases and the
        // ports they talk through (`StoreAdapter`). Files import CellarDomain themselves; nothing
        // is re-exported.
        .target(name: "CellarKit", dependencies: ["CellarDomain"], path: "src/CellarKit", swiftSettings: approachable),

        // Infrastructure: the concrete store adapters behind CellarKit's `StoreAdapter` port. Only
        // a composition root imports it: the CLI's `main`, the app's `main.swift` and the tests'
        // set-up. No view, store or UI type may (ArchitectureTests).
        .target(name: "CellarInfrastructure", dependencies: ["CellarKit", "CellarDomain"], path: "src/CellarInfrastructure",
                swiftSettings: approachable),

        // Thin CLI over CellarKit.
        .executableTarget(name: "cellar",
            dependencies: [
                "CellarKit",
                "CellarDomain",
                "CellarInfrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ], path: "src/cellar",
            swiftSettings: approachable
        ),

        // The app's presentation primitives — the store marks, the lockups, the generated cover —
        // in a library rather than in the executable, because a test cannot import an executable.
        // This is what makes a user-visible change verifiable without launching the app.
        .target(name: "CellarUI", dependencies: ["CellarKit", "CellarDomain"], path: "src/CellarUI", swiftSettings: mainActorByDefault),

        // Phase 3: a native SwiftUI "Steam-like" front-end over the same CellarKit core. Drives the
        // `cellar` CLI as a subprocess for actions, so it reuses every tested path.
        .executableTarget(name: "CellarApp",
            dependencies: ["CellarKit", "CellarDomain", "CellarInfrastructure", "CellarUI", .product(name: "Sparkle", package: "Sparkle")], path: "src/CellarApp",
            // Inside Cellar.app the framework sits in Contents/Frameworks (Scripts/bundle-app.sh);
            // SwiftPM's own @loader_path rpath still finds it beside the binary in .build.
            swiftSettings: mainActorByDefault,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),

        .testTarget(name: "CellarKitTests", dependencies: ["CellarKit", "CellarDomain", "CellarInfrastructure"], path: "tests/CellarKitTests"),

        // Renders the marks offscreen and measures them. Needs the profile database and the golden
        // images on disk, so it is handed the repo root rather than guessing from #filePath.
        .testTarget(name: "CellarUITests", dependencies: ["CellarUI", "CellarKit", "CellarDomain"], path: "tests/CellarUITests"),

        // Tiered integration tests. Tier A is hermetic; tiers B and C install a real runner, build
        // a real Wine prefix and run a real Windows executable, and are opt-in behind environment
        // variables so the default run stays fast and CI stays green. See docs/TESTING.md.
        .testTarget(name: "CellarIntegrationTests", dependencies: ["CellarKit", "CellarDomain", "CellarInfrastructure"], path: "tests/CellarIntegrationTests"),
    ],
    // Every target, tests included, is checked in Swift 6 mode: data-race safety is a compile error,
    // not a warning (#77). CellarDomain moved first; the rest followed once CI built with Swift 6.2.
    swiftLanguageModes: [.v6]
)
