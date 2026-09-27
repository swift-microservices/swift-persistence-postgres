//
//  PostgresClient+withClient.swift
//  swift-persistence-postgres
//
//  Created by Zaid Rahhawi on 9/11/26.
//

public import Logging
public import PostgresNIO

extension PostgresClient {
    /// Runs `operation` with a client that lives exactly that long: started in a task group and
    /// cancelled when the operation returns or throws. Queries lease connections from the pool
    /// and wait for one, so nothing warms up before the first query.
    /// The operation preserves its actor isolation, so a closure formed by the caller can use
    /// the caller's actor-local state.
    ///
    /// For a client that outlives one operation, such as the one a long-running service builds
    /// its ``PostgresDatabase`` on, run the client as a service instead.
    ///
    /// ```swift
    /// try await PostgresClient.withClient(configuration: configuration, logger: logger) { client in
    ///     try await migrations.apply(client: client)
    /// }
    /// ```
    public static func withClient<T: Sendable>(
        configuration: PostgresClient.Configuration,
        isolation: isolated (any Actor)? = #isolation,
        logger: Logger,
        operation: (PostgresClient) async throws -> T
    ) async throws -> T {
        let client = PostgresClient(configuration: configuration, backgroundLogger: logger)

        return try await withThrowingTaskGroup { group in
            group.addTask {
                await client.run()
            }
            defer { group.cancelAll() }

            return try await operation(client)
        }
    }
}
