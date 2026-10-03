// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

import Logging
import PersistencePostgres
import PostgresNIO
import Testing

/// `withClient` opens no connection until a query leases one, so these run without a Postgres.
@Suite(.timeLimit(.minutes(1)))
struct PostgresClientWithClientTests {
    struct OperationFailure: Error, Equatable {}

    let logger = Logger(label: "test")

    @Test("The client operation inherits the caller's actor isolation")
    func operationInheritsCallerIsolation() async throws {
        let caller = ClientCaller()
        try await caller.run(logger: logger)
        #expect(await caller.calls == 2)
    }

    @Test("The client operation inherits MainActor isolation across suspension")
    @MainActor
    func operationInheritsMainActorIsolation() async throws {
        let state = LocalState()

        let result = try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { _ in
            MainActor.preconditionIsolated()
            state.calls += 1
            await Task.yield()
            MainActor.preconditionIsolated()
            state.calls += 1
            return state.calls
        }

        #expect(result == 2)
    }

    @Test("Throwing stops the client and rethrows the operation's error")
    @MainActor
    func throwingStopsTheClient() async throws {
        let state = LocalState()

        await #expect(throws: OperationFailure()) {
            try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { _ in
                MainActor.preconditionIsolated()
                state.calls += 1
                throw OperationFailure()
            }
        }

        #expect(state.calls == 1)
    }

    @Test("Cancelling the caller's task reaches the operation and stops the client")
    func cancellationStopsTheClient() async throws {
        let caller = ClientCaller()
        let (started, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let logger = logger

        let operation = Task {
            defer { continuation.finish() }
            try await caller.runUntilCancelled(logger: logger, started: continuation)
        }
        defer { operation.cancel() }

        for await _ in started { break }
        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await caller.calls == 1)
    }
}

private actor ClientCaller {
    private let state = LocalState()

    var calls: Int { state.calls }

    func run(logger: Logger) async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { _ in
            self.preconditionIsolated()
            state.calls += 1
            await Task.yield()
            self.preconditionIsolated()
            state.calls += 1
        }
    }

    func runUntilCancelled(logger: Logger, started: AsyncStream<Void>.Continuation) async throws {
        try await PostgresClient.withClient(configuration: TestDatabase.configuration(), logger: logger) { _ in
            self.preconditionIsolated()
            state.calls += 1
            started.yield(())
            try await Task.sleep(for: .seconds(60))
            state.calls += 1
        }
    }
}
