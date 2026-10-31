// swift-tools-version: 6.2
import PackageDescription

/// The domain: pure types and policies — the stores' table of facts, launch stages, install phases,
/// the events a command reports. Foundation only, no I/O, and no dependency at all: a package that
/// declares none cannot import anything of Cellar's, so the compiler keeps it pure (#133).
let package = Package(
    name: "CellarDomain",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CellarDomain", targets: ["CellarDomain"]),
    ],
    targets: [
        .target(
            name: "CellarDomain",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
