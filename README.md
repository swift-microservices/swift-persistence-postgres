# Swift Persistence Postgres

[![Documentation](https://img.shields.io/badge/docc-read_documentation-blue)](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres/documentation)
[![Release](https://img.shields.io/github/v/release/swift-microservices/swift-persistence-postgres)](https://github.com/swift-microservices/swift-persistence-postgres/releases)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-microservices%2Fswift-persistence-postgres%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres)
[![CI](https://github.com/swift-microservices/swift-persistence-postgres/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/swift-microservices/swift-persistence-postgres/actions/workflows/ci.yml)

The Postgres driver for [swift-persistence](https://github.com/swift-microservices/swift-persistence).
It runs each unit of work in a transaction over a PostgresNIO `PostgresClient`, and applies
per-transaction settings so that Postgres row-level security can isolate one caller from another.

- 🚀 One type, `PostgresDatabase`, turns a connection pool into a swift-persistence `Database`
- 🔒 Per-call settings for row-level security, bound once where the caller becomes known
- 📦 Built on [PostgresNIO](https://github.com/vapor/postgres-nio) 1.33.1, with no query layer
  of its own
- 🔧 Swift 6.3, macOS 15 or Linux, tested against PostgreSQL 18

🔗 Jump to:
- 📖 [Overview](#-overview)
- 🏁 [Getting Started](#-getting-started)
- 📘 [Documentation](#-documentation)
- 🧰 [Release Info](#-release-info)
- 🛠️ [Support](#%EF%B8%8F-support)

## 📖 Overview

swift-persistence describes the transaction boundary of an application: a use case asks a
`Database` for a transaction and receives a scope holding the repositories it may touch. This
package is that database for Postgres. Each unit of work borrows a connection from the pool,
begins a transaction, applies the settings for the call, builds your scope on that connection, and
hands it to the work. Returning commits; throwing rolls back and rethrows the same error, unwrapped
from PostgresNIO's transaction error, so a use case catches the error its repository threw.

Repositories use PostgresNIO directly. This package adds no query, row, or connection abstraction;
the driver's types are that layer.

**Key Features:**
- 🔄 **Transactions**: Every unit of work is a transaction, and every repository in the scope
  shares its connection
- 🔒 **Row-level security**: Settings are applied with `set_config(name, value, true)`, so they are
  local to the transaction and a pooled connection never carries one caller into the next
- 🧵 **Actor isolation**: The transaction closure keeps the caller's actor isolation, including
  across suspension, so an actor can use its own state inside it
- ⏱️ **Clients for one operation**: `PostgresClient.withClient` runs a client for exactly as long
  as one operation, such as applying migrations at startup

## 🏁 Getting Started

### Prerequisites

- Swift version: Swift 6.3+
- Platforms: macOS 15+ or Linux
- A PostgreSQL server (tested against PostgreSQL 18)

To install/upgrade Swift, see https://www.swift.org/install/

### Adding as a dependency

Add the package, and the libraries your repositories use alongside it, to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-microservices/swift-persistence-postgres.git", from: "1.0.0"),
    .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
],
targets: [
    .target(
        name: "PostsService",
        dependencies: [
            .product(name: "PersistencePostgres", package: "swift-persistence-postgres"),
            .product(name: "PostgresNIO", package: "postgres-nio"),
            .product(name: "Logging", package: "swift-log"),
        ]
    ),
]
```

A target that imports `Persistence` or `OperationContext` itself, as the later examples do, also
adds [swift-persistence](https://github.com/swift-microservices/swift-persistence) or
[swift-operation-context](https://github.com/swift-microservices/swift-operation-context)
`from: "1.0.0"` and the product of the same name.

### Usage

#### Creating a database and running a transaction

Declare a scope that builds your repositories on the transaction's connection, build one
`PostgresDatabase` over the client, and run work in `withTransaction`:

```swift
import Logging
import PersistencePostgres
import PostgresNIO

// Your repository, written with PostgresNIO on the connection it is given.
struct PostRepository: Sendable {
    let connection: PostgresConnection
    let logger: Logger

    func create(title: String) async throws {
        try await connection.query("INSERT INTO posts (title) VALUES (\(title))", logger: logger)
    }

    func titles() async throws -> [String] {
        try await connection.query("SELECT title FROM posts ORDER BY title", logger: logger)
            .decode(String.self)
            .reduce(into: [String]()) { $0.append($1) }
    }
}

// The scope: every repository a transaction may use, built on that transaction's connection.
struct PostgresPostsScope: PostgresScope {
    let postRepository: PostRepository

    init(connection: PostgresConnection, logger: Logger) {
        self.postRepository = PostRepository(connection: connection, logger: logger)
    }
}

let logger = Logger(label: "posts")
let configuration = PostgresClient.Configuration(
    host: "localhost",
    username: "posts_service",
    password: "secret",
    database: "posts",
    tls: .disable
)

try await PostgresClient.withClient(configuration: configuration, logger: logger) { client in
    // Constant settings apply to every transaction this database begins.
    let database = PostgresDatabase<PostgresPostsScope>(
        client: client,
        settings: ["application_name": "posts"],
        logger: logger
    )

    // One transaction: commits when the closure returns, rolls back if it throws.
    let titles = try await database.withTransaction { scope in
        try await scope.postRepository.create(title: "Hello, Postgres")
        return try await scope.postRepository.titles()
    }
    print(titles)
}
```

`withClient` starts the client in a task group and cancels it when the operation returns or
throws, which suits a short program or migrations at startup. A long-running service instead runs
its `PostgresClient` as a service (it is a ServiceLifecycle `Service`, so it can join your
`ServiceGroup`) and builds the database on it once.

Finish all work using the scope before the closure returns or throws. The scope and its
repositories are bound to the transaction: don't retain them, or use them from tasks that outlive
the closure. While the closure is suspended, other work on the caller's actor may run, and a
rollback does not undo changes the closure made to in-memory state.

#### Row-level security with a per-transaction setting

Settings that differ from call to call, such as who is calling, are bound in the task's
`OperationContext` where the caller becomes known, typically your authentication middleware. Every
transaction begun under that task applies them over the database's constant settings, and a
setting bound in the context wins over a constant of the same name. With `database` from the
first example:

```swift
import Foundation
import OperationContext
import PersistencePostgres

/// Runs `operation` with every transaction it begins scoped to `callerId`.
func withCaller<T>(_ callerId: UUID, operation: () async throws -> T) async throws -> T {
    var operationContext = OperationContext.current
    operationContext.postgresSettings = ["app.caller_user_id": callerId.uuidString.lowercased()]
    return try await OperationContext.withContext(operationContext) {
        try await operation()
    }
}

// `callerId` is the authenticated user's ID, from your authentication layer.
let titles = try await withCaller(callerId) {
    try await database.withTransaction { scope in
        try await scope.postRepository.titles()
    }
}
```

A row-level security policy on a `posts` table with an `author_id` column reads the caller back,
for reads and for writes:

```sql
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY posts_by_author ON posts
    USING (author_id = NULLIF(current_setting('app.caller_user_id', true), '')::uuid)
    WITH CHECK (author_id = NULLIF(current_setting('app.caller_user_id', true), '')::uuid);
```

Things to know before relying on it:

- **Enable it on the table.** A policy takes effect only on a table with
  `ENABLE ROW LEVEL SECURITY`, as above.
- **Connect as a policed role.** Policies do not apply to superusers, to roles with `BYPASSRLS`, or
  to the table's owner unless the table also has `FORCE ROW LEVEL SECURITY`. The service must
  connect as a role that is none of these.
- **Keep the `NULLIF`.** Once a pooled connection has carried the setting, reading it in a later
  transaction yields `''` rather than `NULL`, and `''::uuid` is an error rather than a non-match.
- **Settings end with the transaction.** Each one is applied with `set_config(name, value, true)`:
  visible to every statement inside the transaction, gone when it ends by commit or by rollback.
  With no caller bound, a policy like this one returns no rows.

The [Row-level security](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres/documentation/persistencepostgres/rowlevelsecurity)
article covers where policies end and use cases begin, and how to handle work that must see every
tenant.

#### Writing use cases against `Database`

Use cases don't name this package. Each declares the scope it needs as a protocol and takes
`any Database<ThatScope>` from swift-persistence; the Postgres scope conforms to every use case's
protocol, and the composition root passes the `PostgresDatabase` in:

```swift
import Persistence

protocol ListPostsUseCaseScope: Sendable {
    var postRepository: PostRepository { get }
}

struct ListPostsUseCase<Scope: ListPostsUseCaseScope> {
    let database: any Database<Scope>

    func callAsFunction() async throws -> [String] {
        try await database.withTransaction { scope in
            try await scope.postRepository.titles()
        }
    }
}

extension PostgresPostsScope: ListPostsUseCaseScope {}

let listPosts = ListPostsUseCase<PostgresPostsScope>(database: database)
```

In a real service the scope protocol names a repository protocol rather than the Postgres type, so
tests can hand the use case a database whose scope holds in-memory repositories.

## 📘 Documentation

- [API Documentation](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres/documentation/persistencepostgres)
  - The full API reference, on Swift Package Index
- [Row-level security](https://swiftpackageindex.com/swift-microservices/swift-persistence-postgres/documentation/persistencepostgres/rowlevelsecurity)
  - Binding the tenant to the transaction so that policies can isolate it
- [swift-persistence: Transactions and scopes](https://swiftpackageindex.com/swift-microservices/swift-persistence/documentation/persistence/transactionsandscopes)
  - What a transaction hands to the work inside it, and how a use case asks for it
- [swift-operation-context](https://github.com/swift-microservices/swift-operation-context) - The
  task-local context the per-call settings are bound in

## 🧰 Release Info

- Versioning: [Semantic Versioning](https://semver.org). The public API is stable from 1.0.0, and
  only a major release breaks it; CI checks every pull request for API breakage.
- Release notes: [GitHub Releases](https://github.com/swift-microservices/swift-persistence-postgres/releases)
- Swift versions: CI tests Swift 6.3 and 6.4 on Linux (x86_64 and aarch64, plus the static Linux
  SDK), along with nightly toolchains, against PostgreSQL 18.
- Dependencies: PostgresNIO 1.33.1, swift-persistence 1.0, swift-operation-context 1.0, swift-log
  1.15.

## 🛠️ Support

If you have any questions or need help, feel free to reach out by
[opening an issue](https://github.com/swift-microservices/swift-persistence-postgres/issues).

Pull requests are welcome. Keep a change focused, prove new behaviour with a test, and label the
pull request with its semantic version impact.

### Development

The database tests run against a real Postgres named by `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`, and fail when `POSTGRES_HOST` is unset:
a driver test with no database proves nothing. `scripts/test.sh` provides one, using a Homebrew
PostgreSQL 18 if installed and otherwise a `postgres:18` container through `docker` or
`container`; with `POSTGRES_HOST` already set, it uses that database instead.

```sh
scripts/test.sh                                                      # starts an ephemeral Postgres, runs swift test, stops it
swift-format lint --strict --recursive Package.swift Sources Tests  # what the soundness check runs
```

## License

MIT. See [LICENSE](LICENSE).
