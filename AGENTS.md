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
- Use the checked-in `.swift-format`, copied exactly from apple/swift-temporal-sdk at
  `508797b5468dbc532f77c317bf9df0cb3231f5c1`: four-space indentation, 150-column lines,
  and ordered imports. Format all tracked Swift files, including `Package.swift`, and run
  `swift-format lint --strict`. Public documentation remains a repository requirement even
  though this formatter does not enforce it.
- File headers follow the existing files: name, package, author, date.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases, created by the Auto Release workflow: run it by hand on `main`
  and it computes the next version from the labels of the pull requests merged since the last
  release, tags it, and writes the notes from `.github/release.yml`. A major bump is refused
  there and is cut by hand.
- Consumers pin by tag, never by branch or path.

## Library CI profile

- This repository profile overrides general service CI and formatting defaults. Libraries
  never commit `Package.resolved`; CI resolves released dependencies from the manifest.
- PRs run soundness checks, including API compatibility, documentation, formatting, shellcheck,
  and yamllint. The docs workflow adds the DocC plugin only in its temporary checkout.
  License-header checking stays disabled because source files use the author-header convention.
- PRs, main pushes, and the weekly schedule run Linux tests on Swift 6.3 and 6.4, next/main
  snapshots, release builds, and static Linux SDK compatibility. Require supported stable
  checks in branch protection; snapshot failures remain visible and advisory unless
  maintainers explicitly require them.
- CI is Linux-only by project choice. macOS and other Apple-platform builds/tests are
  outside this pipeline; Linux success does not establish Apple-platform compatibility.
- Actions and reusable workflows are SHA-pinned. The reviewed SwiftNIO main commit supplies
  Swift 6.4 inputs absent from release 2.103.0; its nested workflows and downloaded scripts
  still follow upstream main. Caller pins do not make that execution chain immutable.
- Database tests use a custom Linux matrix with a healthy PostgreSQL 18 service. Wait for
  `pg_isready` over TCP; an open forwarded port or temporary Unix-only bootstrap server
  does not establish database readiness.
- Full Foundation linking is an upstream PostgresNIO dependency exception; retain the static
  SDK compatibility build and use FoundationEssentials in our own code where available.
