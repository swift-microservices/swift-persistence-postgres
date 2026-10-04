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

## Library CI profile

- This repository profile overrides general service CI and formatting defaults. Libraries
  never commit `Package.resolved`; CI resolves released dependencies from the manifest.
- PRs run documentation, formatting, compact license-header, shellcheck, and yamllint checks.
  Automatic API-breakage checking is disabled by project choice; SemVer labels still describe
  the public API impact. The docs workflow adds the DocC plugin only in its temporary checkout.
- PRs and main pushes run Linux tests on Swift 6.3 and 6.4, next/main snapshots, and release
  builds. PRs also run x86_64 static Linux SDK builds against the released and Swift main SDKs.
  CI has no scheduled runs. Require supported stable checks in branch protection; snapshot
  failures remain visible and advisory unless maintainers explicitly require them.
- Static SDK checks follow Swift Temporal SDK's PR-only setup and cross-compile only.
- CI is Linux-only by project choice. macOS and other Apple-platform builds/tests are
  outside this pipeline; Linux success does not establish Apple-platform compatibility.
- Shared library workflows and the SwiftNIO SemVer action follow `@main` by project choice.
  Soundness uses its release tag, and standard Actions use major-version tags. These moving
  references include upstream changes; do not describe them as immutable.
- Dependabot checks weekly, targets main, and labels workflow-update PRs `semver/none`.
- Use the three-line MIT header matched by `.license_header_template`. Keep the tools-version
  directive first in `Package.swift`, followed by that header. `.licenseignore` excludes the
  manifest (the upstream checker requires a header at line one) and the plain-text `LICENSE`.
- Database tests use a custom Linux matrix with a healthy PostgreSQL 18 service. Wait for
  `pg_isready` over TCP; an open forwarded port or temporary Unix-only bootstrap server
  does not establish database readiness.
- Full Foundation linking is an upstream PostgresNIO dependency exception; retain the static
  SDK compatibility build and use FoundationEssentials in our own code where available.
