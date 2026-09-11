//
//  PostgresSettings.swift
//  swift-persistence-postgres
//
//  Created by Zaid Rahhawi on 9/11/26.
//

import ServiceContextModule

/// Configuration parameters a ``PostgresDatabase`` applies to each transaction it begins.
///
/// Every entry becomes `set_config(name, value, true)` at the start of the transaction, so it is
/// visible to every statement inside and discarded when the transaction ends, whether by commit
/// or by rollback. A parameter can be any Postgres setting, such as `statement_timeout`, or a
/// custom one the application's policies read back with `current_setting`:
///
/// ```swift
/// let settings: PostgresSettings = ["app.caller_user_id": userId.uuidString.lowercased()]
/// ```
///
/// Constant settings are passed to the database when it is built. Settings that differ from one
/// call to the next, such as who is calling, are bound in the task's `ServiceContext` under
/// ``ServiceContextModule/ServiceContext/postgresSettings`` by whatever layer establishes the caller,
/// and the database reads them as each transaction begins.
public struct PostgresSettings: Sendable, Hashable, ExpressibleByDictionaryLiteral {
    private var values: [String: String]

    /// An empty set of settings.
    public init() {
        self.values = [:]
    }

    /// Settings from a dictionary of parameter names to values.
    public init(_ values: [String: String]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { $1 })
    }

    /// The value of a parameter, or `nil` if it is not set.
    public subscript(name: String) -> String? {
        get { values[name] }
        set { values[name] = newValue }
    }

    /// Whether no parameter is set.
    public var isEmpty: Bool {
        values.isEmpty
    }

    /// These settings with `other` applied over them. Where both set a parameter, `other` wins.
    public func merging(_ other: PostgresSettings) -> PostgresSettings {
        PostgresSettings(values.merging(other.values, uniquingKeysWith: { $1 }))
    }

    /// The parameters in name order, which is the order they are applied in.
    public var sorted: [(name: String, value: String)] {
        values.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
    }
}

/// The `ServiceContext` key under which the settings for the current call are bound.
public enum PostgresSettingsKey: ServiceContextKey {
    public typealias Value = PostgresSettings

    public static let nameOverride: String? = "postgres-settings"
}

extension ServiceContext {
    /// The settings a ``PostgresDatabase`` applies to every transaction begun under this context,
    /// over the constant ones it was built with.
    ///
    /// Bind them where the caller becomes known:
    ///
    /// ```swift
    /// var context = ServiceContext.current ?? .topLevel
    /// context.postgresSettings = ["app.caller_user_id": caller.id.uuidString.lowercased()]
    /// return try await ServiceContext.withValue(context) {
    ///     try await next(request, context)
    /// }
    /// ```
    public var postgresSettings: PostgresSettings? {
        get { self[PostgresSettingsKey.self] }
        set { self[PostgresSettingsKey.self] = newValue }
    }
}
