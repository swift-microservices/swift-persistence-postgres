# Repository guidelines

This package is the Postgres driver for swift-persistence. Read this before changing anything.

## What this package is

- One product, `PersistencePostgres`: `PostgresDatabase`, `PostgresScope`, `PostgresSettings`,
  the `OperationContext` key the settings are bound under, and `PostgresClient.withClient` for a
  client that lives as long as one operation.
- It depends on swift-persistence by tag, PostgresNIO, swift-log, and swift-operation-context.
  Nothing else.
- Every unit of work is a transaction. Settings are applied with `set_config(name, value, true)`
  and are therefore transaction-local.

## What does not belong here

- `withConnection` or any path that runs statements outside a transaction. Settings are
  transaction-local by design; a session-scoped caller on a pooled connection would leak to the
  next borrower.
- Query, row, or connection abstractions. PostgresNIO's types are that layer.
- Knowledge of what a caller is. The application binds `OperationContext.postgresSettings` where it
  establishes the caller; this package only reads them.
- Migrations, pool configuration, TLS. Those are the composition root's.

## Swift

- Swift 6.3, strict concurrency, `Sendable` everywhere it is meaningful.
- Logger is the last parameter of every initializer and has no default.
- Tests use Swift Testing and run against a real Postgres; `scripts/test.sh` starts one. The
  database suite fails, rather than skips, when `POSTGRES_HOST` is unset. Every behaviour the
  database promises has a test: caller isolation from an actor and from `@MainActor` across a
  query, commit on return, rollback and unwrapped rethrow on throw, rollback and cleared settings
  on cancellation, settings visible inside and gone after commit and rollback, constant and
  context settings merged with context winning, scope built on the transaction's connection.
- `withClient` is proven without a server: caller isolation, a thrown error stopping the client
  and reaching the caller, and cancellation stopping the client.
- Doc comments on every public declaration; the DocC catalog is the long-form explanation.
- Use the checked-in `.swift-format`, copied exactly from apple/swift-temporal-sdk at
  `508797b5468dbc532f77c317bf9df0cb3231f5c1`: four-space indentation, 150-column lines,
  and ordered imports. Format all tracked Swift files, including `Package.swift`, and run
  `swift-format lint --strict`. Public documentation remains a repository requirement even
  though this formatter does not enforce it.
- File headers use the compact license format documented below.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases, created by the Auto Release workflow: run it by hand on `main`
  and it computes the next version from the labels of the pull requests merged since the last
  release, tags it, and writes the notes from `.github/release.yml`. A major bump is refused
  there and is cut by hand.
- Consumers pin by tag, never by branch or path.

## CI

The standard library CI from the swift-microservices delivery skill
([library-ci.md](https://github.com/swift-microservices/skills/blob/main/skills/delivering-swift-services/references/library-ci.md)).
Exceptions:

- Tests run in `.github/workflows/tests.yml` beside a PostgreSQL 18 service, because swiftlang's
  `swift_package_test.yml` cannot attach one: the same toolchains and flags, `swift test -c release
  --parallel`, health-checked with `pg_isready` over TCP. Pull requests keep swiftlang's static SDK
  builds with its tests turned off.
- No Foundation-linking job: the one library product, `PersistencePostgres`, depends on PostgresNIO
  1.33, which links full Foundation. Owned code uses FoundationEssentials where available. Revisit
  when PostgresNIO no longer requires full Foundation.
