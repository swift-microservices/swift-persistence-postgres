// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

import Logging
import Persistence
import PersistencePostgres
import PostgresNIO
import ServiceContextModule
import Testing

@Suite(
    .requiresDatabase,
    .serialized,
    .timeLimit(.minutes(1))
)
struct PostgresDatabaseTests {
    struct PostNotFound: Error, Equatable {}

    let logger = Logger(label: "test")

    @Test("A transaction preserves the caller's actor isolation across a database query")
    func transactionInheritsCallerIsolation() async throws {
        let caller = TransactionCaller()
        try await caller.run(logger: logger)
        #expect(await caller.calls == 2)
    }

    @Test("A transaction preserves MainActor isolation across suspension")
    @MainActor
    func transactionInheritsMainActorIsolation() async throws {
        let state = LocalState()
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database: any Database<ConnectionScope> = PostgresDatabase(client: client, logger: logger)

            let result = try await database.withTransaction { scope in
                MainActor.preconditionIsolated()
                state.calls += 1
                try await scope.connection.query("SELECT 1", logger: logger)
                await Task.yield()
                MainActor.preconditionIsolated()
                state.calls += 1
                return state.calls
            }

            #expect(result == 2)
        }
        #expect(state.calls == 2)
    }

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
    @MainActor
    func throwingRollsBack() async throws {
        let state = LocalState()
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database: any Database<ConnectionScope> = PostgresDatabase(client: client, logger: logger)
            let table = "rollbacks_\(UInt32.random(in: 0...UInt32.max))"

            await #expect(throws: PostNotFound()) {
                try await database.withTransaction { scope in
                    MainActor.preconditionIsolated()
                    state.calls += 1
                    try await scope.connection.query("CREATE TABLE \(unescaped: table) (title TEXT)", logger: logger)
                    MainActor.preconditionIsolated()
                    state.calls += 1
                    throw PostNotFound()
                }
            }

            let exists = try await database.withTransaction { scope in
                let rows = try await scope.connection.query("SELECT to_regclass(\(table)) IS NOT NULL", logger: logger)
                var exists: [Bool] = []
                for try await value in rows.decode(Bool.self) {
                    exists.append(value)
                }
                return exists
            }
            #expect(exists == [false])
            #expect(state.calls == 2)
        }
    }

    @Test("Cancellation rolls back work and clears settings before the connection is reused")
    func cancellationRollsBack() async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(maximumConnections: 1), logger: logger) { client in
            let database: any Database<ConnectionScope> = PostgresDatabase(client: client, logger: logger)
            let table = "cancelled_\(UInt32.random(in: 0...UInt32.max))"
            let (started, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

            let transaction = Task {
                defer { continuation.finish() }
                var context = ServiceContext.topLevel
                context.postgresSettings = ["app.caller_user_id": "cancelled-caller"]
                try await ServiceContext.withValue(context) {
                    try await database.withTransaction { scope in
                        #expect(try await scope.setting("app.caller_user_id") == "cancelled-caller")
                        try await scope.connection.query("CREATE TABLE \(unescaped: table) (title TEXT)", logger: logger)
                        continuation.yield(())
                        try await Task.sleep(for: .seconds(60))
                    }
                }
            }
            defer { transaction.cancel() }

            // Cancel only after the transaction has performed a write. Finishing the stream
            // also releases this wait if setup fails before the signal.
            for await _ in started { break }
            transaction.cancel()
            await #expect(throws: CancellationError.self) { try await transaction.value }

            let (exists, setting) = try await database.withTransaction { scope in
                let exists = try await scope.connection.query("SELECT to_regclass(\(table)) IS NOT NULL", logger: logger)
                    .decode(Bool.self)
                    .reduce(into: [Bool]()) { $0.append($1) }
                return (exists, try await scope.setting("app.caller_user_id"))
            }
            #expect(exists == [false])
            #expect(setting == nil)
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

private actor TransactionCaller {
    private let state = LocalState()

    var calls: Int { state.calls }

    func run(logger: Logger) async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { client in
            let database: any Database<ConnectionScope> = PostgresDatabase(client: client, logger: logger)

            let values = try await database.withTransaction { scope in
                self.preconditionIsolated()
                state.calls += 1
                let values = try await scope.connection.query("SELECT 1", logger: logger)
                    .decode(Int.self)
                    .reduce(into: [Int]()) { $0.append($1) }
                await Task.yield()
                self.preconditionIsolated()
                state.calls += 1
                return values
            }

            #expect(values == [1])
        }
    }
}

/// Intentionally non-Sendable to verify actor-local reference captures.
final class LocalState {
    var calls = 0
}
