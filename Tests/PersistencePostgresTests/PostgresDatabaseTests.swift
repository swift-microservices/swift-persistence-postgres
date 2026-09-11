//
//  PostgresDatabaseTests.swift
//  swift-persistence-postgres
//
//  Created by Zaid Rahhawi on 9/11/26.
//

import Logging
import PersistencePostgres
import PostgresNIO
import ServiceContextModule
import Testing

@Suite(.enabled(if: TestDatabase.isConfigured, "Set POSTGRES_HOST to run against a Postgres; scripts/test.sh starts one."), .serialized)
struct PostgresDatabaseTests {
    struct PostNotFound: Error, Equatable {}

    let logger = Logger(label: "test")

    @Test("Returning commits the work")
    func returningCommits() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(client: client, logger: logger)
            let table = "commits_\(UInt32.random(in: 0...UInt32.max))"

            try await database.withTransaction { scope in
                try await scope.connection.query("CREATE TABLE \(unescaped: table) (title TEXT)", logger: logger)
                try await scope.connection.query("INSERT INTO \(unescaped: table) VALUES ('Hello')", logger: logger)
            }

            let titles = try await database.withTransaction { scope in
                try await scope.connection.query("SELECT title FROM \(unescaped: table)", logger: logger)
                    .decode(String.self)
                    .reduce(into: [String]()) { $0.append($1) }
            }
            #expect(titles == ["Hello"])

            try await database.withTransaction { scope in
                _ = try await scope.connection.query("DROP TABLE \(unescaped: table)", logger: logger)
            }
        }
    }

    @Test("Throwing rolls the work back and rethrows the same error, unwrapped")
    func throwingRollsBack() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(client: client, logger: logger)
            let table = "rollbacks_\(UInt32.random(in: 0...UInt32.max))"

            await #expect(throws: PostNotFound()) {
                try await database.withTransaction { scope in
                    try await scope.connection.query("CREATE TABLE \(unescaped: table) (title TEXT)", logger: logger)
                    throw PostNotFound()
                }
            }

            let exists = try await database.withTransaction { scope in
                try await scope.connection.query("SELECT to_regclass(\(table)) IS NOT NULL", logger: logger)
                    .decode(Bool.self)
                    .reduce(into: [Bool]()) { $0.append($1) }
            }
            #expect(exists == [false])
        }
    }

    @Test("Settings bound in the ServiceContext are visible inside the transaction")
    func contextSettingsApply() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(client: client, logger: logger)

            var context = ServiceContext.topLevel
            context.postgresSettings = ["app.caller_user_id": "user-1"]

            let value = try await ServiceContext.withValue(context) {
                try await database.withTransaction { scope in
                    try await scope.setting("app.caller_user_id")
                }
            }
            #expect(value == "user-1")
        }
    }

    @Test("Settings are gone after commit and after rollback")
    func settingsAreTransactionLocal() async throws {
        // One connection in the pool, so every transaction reuses the one that was configured.
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(maximumConnections: 1), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(client: client, logger: logger)
            var context = ServiceContext.topLevel
            context.postgresSettings = ["app.caller_user_id": "user-1"]

            try await ServiceContext.withValue(context) {
                try await database.withTransaction { _ in }
            }
            let afterCommit = try await database.withTransaction { scope in
                try await scope.setting("app.caller_user_id")
            }
            #expect(afterCommit == nil)

            await #expect(throws: PostNotFound()) {
                try await ServiceContext.withValue(context) {
                    try await database.withTransaction { _ in throw PostNotFound() }
                }
            }
            let afterRollback = try await database.withTransaction { scope in
                try await scope.setting("app.caller_user_id")
            }
            #expect(afterRollback == nil)
        }
    }

    @Test("Constant settings apply to every transaction; context settings win on the same name")
    func constantSettingsMerge() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(
                client: client,
                settings: ["app.caller_role": "anonymous", "application_name": "tests"],
                logger: logger
            )

            let unbound = try await database.withTransaction { scope in
                (try await scope.setting("app.caller_role"), try await scope.setting("application_name"))
            }
            #expect(unbound.0 == "anonymous")
            #expect(unbound.1 == "tests")

            var context = ServiceContext.topLevel
            context.postgresSettings = ["app.caller_role": "user"]
            let bound = try await ServiceContext.withValue(context) {
                try await database.withTransaction { scope in
                    (try await scope.setting("app.caller_role"), try await scope.setting("application_name"))
                }
            }
            #expect(bound.0 == "user")
            #expect(bound.1 == "tests")
        }
    }

    @Test("A scope is built on the transaction's own connection")
    func scopeSharesTheTransaction() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database = PostgresDatabase<ConnectionScope>(client: client, logger: logger)

            let sawOwnRow = try await database.withTransaction { scope in
                try await scope.connection.query("CREATE TEMP TABLE scoped (n INT) ON COMMIT DROP", logger: logger)
                try await scope.connection.query("INSERT INTO scoped VALUES (1)", logger: logger)
                return try await scope.connection.query("SELECT count(*) FROM scoped", logger: logger)
                    .decode(Int.self)
                    .reduce(into: [Int]()) { $0.append($1) }
            }
            #expect(sawOwnRow == [1])
        }
    }
}
