# ``PersistencePostgres``

The Postgres driver for `Persistence`: transactions over a `PostgresClient`, with per-transaction settings.

## Overview

``PostgresDatabase`` is a `Database` over a PostgresNIO connection pool. Each unit of work
borrows a connection, begins a transaction, applies the ``PostgresSettings`` for the call,
builds the application's ``PostgresScope`` on that connection, and hands it to the work.

Repositories inside the scope use PostgresNIO directly. This package adds no query, row, or
connection abstraction of its own; the driver's types are that layer.

## Example

The application's scope builds its repositories on the transaction's connection, and the
composition root builds one database over the pool:

```swift
struct PostgresPostsScope: PostgresScope, CreatePostUseCaseScope {
    let postRepository: any PostRepository

    init(connection: PostgresConnection, logger: Logger) {
        self.postRepository = PostgresPostRepository(connection: connection, logger: logger)
    }
}

let database = PostgresDatabase<PostgresPostsScope>(
    client: client,
    settings: ["application_name": "posts"],
    logger: logger
)
```

Where the caller becomes known, its settings are bound for every transaction under that task:

```swift
var context = ServiceContext.current ?? .topLevel
context.postgresSettings = ["app.caller_user_id": caller.id.uuidString.lowercased()]
return try await ServiceContext.withValue(context) {
    try await next(request, context)
}
```

## Topics

### The database

- ``PostgresDatabase``
- ``PostgresScope``

### Settings

- ``PostgresSettings``
- ``PostgresSettingsKey``
- ``ServiceContextModule/ServiceContext/postgresSettings``

### A client for one operation

- ``PostgresNIO/PostgresClient/withClient(configuration:logger:operation:)``
- ``PostgresNIO/PostgresClient/withClient(configuration:isolation:logger:operation:)``

### Design

- <doc:RowLevelSecurity>
