// swift-tools-version: 6.3
import PackageDescription

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
        .package(url: "https://github.com/swift-microservices/swift-persistence.git", from: "0.1.0"),
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
            ]
        ),
        .testTarget(
            name: "PersistencePostgresTests",
            dependencies: [
                .target(name: "PersistencePostgres"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
    ]
)
