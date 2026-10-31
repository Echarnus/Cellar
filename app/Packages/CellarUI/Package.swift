// swift-tools-version: 6.2
import PackageDescription

/// The app's presentation primitives — the store marks, the lockups, the generated cover, the
/// progress bar and `Snapshot` — in a library rather than in the executable, because a test cannot
/// import an executable. It sees the domain and the engine, never the infrastructure (#133).
let package = Package(
    name: "CellarUI",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CellarUI", targets: ["CellarUI"]),
    ],
    dependencies: [
        .package(path: "../CellarDomain"),
        .package(path: "../CellarKit"),
    ],
    targets: [
        .target(
            name: "CellarUI",
            dependencies: [
                .product(name: "CellarDomain", package: "CellarDomain"),
                .product(name: "CellarKit", package: "CellarKit"),
            ],
            // UI modules start on the main actor (SE-0466), with Approachable Concurrency.
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
