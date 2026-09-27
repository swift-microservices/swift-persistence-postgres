//
//  PostgresScope.swift
//  swift-persistence-postgres
//
//  Created by Zaid Rahhawi on 9/11/26.
//

public import Logging
public import PostgresNIO

/// A scope a ``PostgresDatabase`` can build on a transaction's connection.
///
/// The application declares its scope as a struct holding its repositories, each constructed on
/// the connection it is given, so every operation inside the transaction shares that connection:
///
/// ```swift
/// struct PostgresPostsScope: PostgresScope, CreatePostUseCaseScope {
///     let postRepository: any PostRepository
///
///     init(connection: PostgresConnection, logger: Logger) {
///         self.postRepository = PostgresPostRepository(connection: connection, logger: logger)
///     }
/// }
/// ```
public protocol PostgresScope: Sendable {
    /// Builds the scope on the connection of the transaction that is about to run.
    ///
    /// - Parameters:
    ///   - connection: The transaction's connection. Valid only for the length of the transaction.
    ///   - logger: The database's logger, to pass to every query.
    init(connection: PostgresConnection, logger: Logger)
}
