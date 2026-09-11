//
//  TestDatabase.swift
//  swift-persistence-postgres
//
//  Created by Zaid Rahhawi on 9/11/26.
//

import Foundation
import Logging
import PersistencePostgres
import PostgresNIO

/// The Postgres the tests run against, named by `POSTGRES_HOST`, `POSTGRES_PORT`,
/// `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`. `scripts/test.sh` starts one.
enum TestDatabase {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil
    }

    static func configuration(maximumConnections: Int? = nil) -> PostgresClient.Configuration {
        let environment = ProcessInfo.processInfo.environment
        var configuration = PostgresClient.Configuration(
            host: environment["POSTGRES_HOST"] ?? "localhost",
            port: environment["POSTGRES_PORT"].flatMap(Int.init) ?? 5432,
            username: environment["POSTGRES_USER"] ?? "postgres",
            password: environment["POSTGRES_PASSWORD"],
            database: environment["POSTGRES_DB"] ?? "postgres",
            tls: .disable
        )
        if let maximumConnections {
            configuration.options.maximumConnections = maximumConnections
        }
        return configuration
    }
}

/// The scope under test: the transaction's connection, so a test can query inside it.
struct ConnectionScope: PostgresScope {
    let connection: PostgresConnection
    let logger: Logger

    func setting(_ name: String) async throws -> String? {
        let rows = try await connection.query("SELECT current_setting(\(name), true)", logger: logger)
        for try await (value) in rows.decode(String?.self) {
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }
        return nil
    }
}
