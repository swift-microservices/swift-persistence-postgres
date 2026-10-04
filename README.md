# swift-persistence-postgres

[![Documentation](https://img.shields.io/badge/docc-read_documentation-blue)](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres/documentation)

The Postgres driver for [swift-persistence](https://github.com/swift-microservices/swift-persistence):
transactions over a `PostgresClient`, with per-transaction settings for row-level security.

```swift
.package(url: "https://github.com/swift-microservices/swift-persistence-postgres.git", from: "0.2.1"),
```

```swift
.product(name: "PersistencePostgres", package: "swift-persistence-postgres"),
```

## The database

`PostgresDatabase` is a `Database` over a PostgresNIO connection pool. Each unit of work borrows a
connection, begins a transaction, applies the settings for the call, builds the scope on that
connection, and hands it to the work. Returning commits; throwing rolls back and rethrows the same
error, unwrapped.

The transaction closure preserves the caller's actor isolation, including across suspension,
so an actor can use its own state inside the closure.
Other actor work may run during suspension, and database rollback does not undo in-memory
mutations. Finish all work using the scope before returning or throwing; do not retain its
transaction-bound repositories or use them from tasks that outlive the closure.

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

Repositories use PostgresNIO directly. This package adds no query, row, or connection abstraction;
the driver's types are that layer.

## Settings

`PostgresSettings` is a dictionary of configuration parameters. Every entry becomes
`set_config(name, value, true)` at the start of a transaction: visible to every statement inside,
gone when it ends, by commit or by rollback.

Constant settings are given to the database once. Settings that differ per call, such as who is
calling, are bound in the task's `ServiceContext` where the caller becomes known, and each
transaction begun under that task reads them:

```swift
var serviceContext = ServiceContext.current ?? .topLevel
serviceContext.postgresSettings = ["app.caller_user_id": caller.id.uuidString.lowercased()]
return try await ServiceContext.withValue(serviceContext) {
    try await next(request, context)
}
```

A row-level security policy then reads the caller back, for reads and for writes:

```sql
CREATE POLICY posts_by_author ON posts
    USING (author_id = NULLIF(current_setting('app.caller_user_id', true), '')::uuid)
    WITH CHECK (author_id = NULLIF(current_setting('app.caller_user_id', true), '')::uuid);
```

`NULLIF` matters: once a pooled connection has carried the setting, reading it in a later
transaction yields `''` rather than `NULL`, and `''::uuid` is an error rather than a non-match.

## A client for one operation

A long-running service runs its `PostgresClient` as a service and builds the database on it. For
work that needs a client only as long as it runs, such as applying migrations at startup,
`withClient` starts one in a task group and cancels it when the operation returns or throws:

```swift
try await PostgresClient.withClient(configuration: configuration, logger: logger) { client in
    try await migrations.apply(client: client)
}
```

## Requirements

Swift 6.3, macOS 15 or Linux. PostgresNIO 1.33.1, swift-persistence 0.2. Tested against
PostgreSQL 18.

## Development

The database tests run against a real Postgres named by `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`, and fail when `POSTGRES_HOST` is unset:
a driver test with no database proves nothing. `scripts/test.sh` provides one.

```sh
scripts/test.sh                                          # starts an ephemeral Postgres, runs swift test, stops it
swift-format lint --strict --recursive Sources Tests    # what the soundness check runs
```

## Contributing

Pull requests are welcome. Keep a change focused, prove new behaviour with a test, and label the
pull request with its semantic version impact.

## License

MIT. See [LICENSE](LICENSE).
