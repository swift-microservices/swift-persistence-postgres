// swift-tools-version: 6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    .enableUpcomingFeature("ExistentialAny"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
    .enableUpcomingFeature("InternalImportsByDefault"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "swift-persistence-postgres",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PersistencePostgres",
            targets: ["PersistencePostgres"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swift-microservices/swift-persistence.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-service-context.git", from: "1.3.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.0"),
    ],
    targets: [
        .target(
            name: "PersistencePostgres",
            dependencies: [
                .product(name: "Persistence", package: "swift-persistence"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PersistencePostgresTests",
            dependencies: [
                .target(name: "PersistencePostgres"),
                .product(name: "Persistence", package: "swift-persistence"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
