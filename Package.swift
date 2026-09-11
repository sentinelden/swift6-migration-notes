// swift-tools-version: 6.0
//
// swift6-migration-notes — real Swift 6 strict-concurrency migration cases.
//
// The whole point of this package is that the examples COMPILE. Notes about
// concurrency rot faster than almost any other documentation, because the
// diagnostics change between toolchains and advice that was right in 5.10
// quietly becomes wrong. Every fix in Notes/ has its counterpart compiled here
// under full strict concurrency, so CI fails the day an example stops being
// true.

import PackageDescription

let package = Package(
    name: "swift6-migration-notes",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "MigrationCases", targets: ["MigrationCases"])
    ],
    targets: [
        .target(
            name: "MigrationCases",
            path: "Sources/MigrationCases",
            swiftSettings: [
                // Swift 6 language mode is strict concurrency by default.
                // Stated explicitly so the intent survives a tools-version bump.
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MigrationCasesTests",
            dependencies: ["MigrationCases"],
            path: "Tests/MigrationCasesTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
