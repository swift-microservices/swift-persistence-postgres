// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

public import Logging
public import Persistence
public import PostgresNIO
import ServiceContextModule

/// A `Database` over a `PostgresClient` connection pool.
///
/// Each unit of work borrows a connection, begins a transaction, applies the
/// ``PostgresSettings`` for the call, builds the `Scope` on that connection, and hands it to the
/// work. Returning commits; throwing rolls back and rethrows the same error.
///
/// ```swift
/// let database = PostgresDatabase<PostgresPostsScope>(
///     client: client,
///     settings: ["application_name": "posts"],
///     logger: logger
/// )
/// ```
public struct PostgresDatabase<Scope: PostgresScope>: Database {
    private let client: PostgresClient
    private let settings: PostgresSettings
    private let logger: Logger

    /// A database that runs each unit of work in a transaction on a connection from `client`.
    ///
    /// - Parameters:
    ///   - client: The connection pool to borrow from.
    ///   - settings: Parameters applied to every transaction. Settings bound in the task's
    ///     `ServiceContext` are applied over these.
    ///   - logger: Passed to every query, and to each scope this database builds.
    public init(
        client: PostgresClient,
        settings: PostgresSettings = [:],
        logger: Logger
    ) {
        self.client = client
        self.settings = settings
        self.logger = logger
    }

    /// Runs `operation` in a transaction configured for the current call.
    ///
    /// The operation preserves the caller's actor isolation, including across suspension.
    /// Other work on that actor may run while the operation is suspended. Database rollback
    /// does not undo mutations to captured Swift state.
    /// Finish all work using the scope before returning or throwing; its transaction-bound
    /// repositories must not be retained for later use.
    ///
    /// The settings are read from the `ServiceContext` as the transaction begins, because the
    /// caller differs from one call to the next while the database is built once at startup.
    ///
    /// `PostgresTransactionError` is unwrapped to the error that caused the rollback, so a use
    /// case catches the error its repository threw rather than a wrapper around it.
    public func withTransaction<T: Sendable>(
        _ operation: (Scope) async throws -> T
    ) async throws -> T {
        let settings = settings.merging(ServiceContext.current?.postgresSettings ?? [:])

        do {
            return try await client.withTransaction(logger: logger, isolation: #isolation) { connection in
                for (name, value) in settings.sorted {
                    try await connection.query(
                        "SELECT set_config(\(name), \(value), true)",
                        logger: logger
                    )
                }

                return try await operation(Scope(connection: connection, logger: logger))
            }
        } catch let error as PostgresTransactionError {
            throw error.closureError ?? error.beginError ?? error.commitError ?? error.rollbackError ?? error
        }
    }
}
