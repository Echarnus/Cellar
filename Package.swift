// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cellar", targets: ["cellar"]),
        .executable(name: "CellarApp", targets: ["CellarApp"]),
        .library(name: "CellarKit", targets: ["CellarKit"]),
        .library(name: "CellarUI", targets: ["CellarUI"]),
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

        // The app's presentation primitives — the store marks, the lockups, the generated cover —
        // in a library rather than in the executable, because a test cannot import an executable.
        // This is what makes a user-visible change verifiable without launching the app.
        .target(name: "CellarUI", dependencies: ["CellarKit"]),

        // Phase 3: a native SwiftUI "Steam-like" front-end over the same CellarKit core. Drives the
        // `cellar` CLI as a subprocess for actions, so it reuses every tested path.
        .executableTarget(name: "CellarApp", dependencies: ["CellarKit", "CellarUI"]),

        .testTarget(name: "CellarKitTests", dependencies: ["CellarKit"]),

        // Renders the marks offscreen and measures them. Needs the profile database and the golden
        // images on disk, so it is handed the repo root rather than guessing from #filePath.
        .testTarget(name: "CellarUITests", dependencies: ["CellarUI", "CellarKit"]),

        // Tiered integration tests. Tier A is hermetic; tiers B and C install a real runner, build
        // a real Wine prefix and run a real Windows executable, and are opt-in behind environment
        // variables so the default run stays fast and CI stays green. See docs/TESTING.md.
        .testTarget(name: "CellarIntegrationTests", dependencies: ["CellarKit"]),
    ],
    // Pragmatic: a synchronous CLI doesn't need Swift 6 strict-concurrency overhead yet.
    swiftLanguageModes: [.v5]
)
