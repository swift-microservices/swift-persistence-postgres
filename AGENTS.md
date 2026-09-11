# Repository guidelines

This package is the Postgres driver for swift-persistence. Read this before changing anything.

## What this package is

- One product, `PersistencePostgres`: `PostgresDatabase`, `PostgresScope`, `PostgresSettings`,
  the `ServiceContext` key the settings are bound under, and `PostgresClient.withClient` for a
  client that lives as long as one operation.
- It depends on swift-persistence by tag, PostgresNIO, swift-log, and swift-service-context.
  Nothing else.
- Every unit of work is a transaction. Settings are applied with `set_config(name, value, true)`
  and are therefore transaction-local.

## What does not belong here

- `withConnection` or any path that runs statements outside a transaction. Settings are
  transaction-local by design; a session-scoped caller on a pooled connection would leak to the
  next borrower.
- Query, row, or connection abstractions. PostgresNIO's types are that layer.
- Knowledge of what a caller is. The application binds `ServiceContext.postgresSettings` where it
  establishes the caller; this package only reads them.
- Migrations, pool configuration, TLS. Those are the composition root's.

## Swift

- Swift 6.3, strict concurrency, `Sendable` everywhere it is meaningful.
- Logger is the last parameter of every initializer and has no default.
- Tests use Swift Testing and run against a real Postgres; `scripts/test.sh` starts one. Every
  behaviour the database promises has a test: commit on return, rollback and unwrapped rethrow on
  throw, settings visible inside and gone after commit and rollback, constant and context
  settings merged with context winning, scope built on the transaction's connection.
- Doc comments on every public declaration; the DocC catalog is the long-form explanation.
- Format with `swift-format format --in-place --recursive Sources Tests`; the soundness check on
  every pull request runs the same rules, an API breakage check against the base branch, and
  shellcheck and yamllint.
- File headers follow the existing files: name, package, author, date.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases, created by the Auto Release workflow: run it by hand on `main`
  and it computes the next version from the labels of the pull requests merged since the last
  release, tags it, and writes the notes from `.github/release.yml`. A major bump is refused
  there and is cut by hand.
- Consumers pin by tag, never by branch or path.
