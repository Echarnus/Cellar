// swift-tools-version: 6.2
import PackageDescription

/// Approachable Concurrency (WWDC25 268): nonisolated async functions run on the caller's actor
/// (SE-0461), and a conformance can take its type's isolation (SE-0470).
let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// The engine and the adapters that plug into it. It depends on the domain and on nothing of the
/// app's: no UI framework, no view, no store (#133).
let package = Package(
    name: "CellarKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CellarKit", targets: ["CellarKit"]),
        .library(name: "CellarInfrastructure", targets: ["CellarInfrastructure"]),
    ],
    dependencies: [
        .package(path: "../CellarDomain"),
    ],
    targets: [
        // Core engine: environment detection, bottles, runners, profiles, the use cases and the
        // ports they talk through (`StoreAdapter`). Files import CellarDomain themselves; nothing
        // is re-exported.
        .target(
            name: "CellarKit",
            dependencies: [.product(name: "CellarDomain", package: "CellarDomain")],
            swiftSettings: approachable
        ),

        // Infrastructure: the concrete store adapters behind CellarKit's `StoreAdapter` port. Only
        // a composition root imports it: the CLI's `main`, the app's `main.swift` and the tests'
        // set-up. No view, store or UI type may (ArchitectureTests).
        .target(
            name: "CellarInfrastructure",
            dependencies: ["CellarKit", .product(name: "CellarDomain", package: "CellarDomain")],
            swiftSettings: approachable
        ),
    ],
    swiftLanguageModes: [.v6]
)
