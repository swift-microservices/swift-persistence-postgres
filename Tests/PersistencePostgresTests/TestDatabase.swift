// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

import Logging
import PersistencePostgres
import PostgresNIO
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The PostgreSQL instance configured for the tests.
///
/// Connection settings come from `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`,
/// `POSTGRES_PASSWORD`, and `POSTGRES_DB`. `scripts/test.sh` starts an instance.
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

/// Fails each test of a suite that needs PostgreSQL when none is configured, rather than
/// skipping it: a driver test with no database proves nothing.
struct RequiresDatabaseTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        guard test.isSuite || TestDatabase.isConfigured else {
            Issue.record("Set POSTGRES_HOST to run against a Postgres; scripts/test.sh starts one.")
            return
        }
        try await function()
    }
}

extension Trait where Self == RequiresDatabaseTrait {
    /// Fails, rather than skips, each test when `POSTGRES_HOST` is unset.
    static var requiresDatabase: Self { Self() }
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
