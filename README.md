# swift-persistence-postgres

The Postgres driver for [swift-persistence](https://github.com/swift-microservices/swift-persistence):
transactions over a `PostgresClient`, with per-transaction settings for row-level security.

```swift
.package(url: "https://github.com/swift-microservices/swift-persistence-postgres.git", from: "0.1.0"),
```

```swift
.product(name: "PersistencePostgres", package: "swift-persistence-postgres"),
```

## The database

`PostgresDatabase` is a `Database` over a PostgresNIO connection pool. Each unit of work borrows a
connection, begins a transaction, applies the settings for the call, builds the scope on that
connection, and hands it to the work. Returning commits; throwing rolls back and rethrows the same
error, unwrapped.

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
var context = ServiceContext.current ?? .topLevel
context.postgresSettings = ["app.caller_user_id": caller.id.uuidString.lowercased()]
return try await ServiceContext.withValue(context) {
    try await next(request, context)
}
```

A row-level security policy then reads the caller back:

```sql
CREATE POLICY posts_by_author ON posts
    USING (author_id = current_setting('app.caller_user_id', true)::uuid);
```

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

Swift 6.3, macOS 15 or Linux, PostgreSQL 14 or later.

## Development

The tests run against a real Postgres named by `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`,
`POSTGRES_PASSWORD`, and `POSTGRES_DB`, and skip when `POSTGRES_HOST` is unset.

```sh
scripts/test.sh                                          # starts an ephemeral Postgres, runs swift test, stops it
swift-format lint --strict --recursive Sources Tests    # what the soundness check runs
```

## Contributing

Pull requests are welcome. Keep a change focused, prove new behaviour with a test, and label the
pull request with its semantic version impact.

## License

MIT. See [LICENSE](LICENSE).
