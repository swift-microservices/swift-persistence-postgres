# Row-level security

Binding the tenant to the transaction so that policies can isolate it.

## Policies isolate tenants

Postgres row-level security is tenant isolation: a policy on a table decides which rows a
statement sees, and the policy can read the tenant from a configuration parameter with
`current_setting`:

```sql
CREATE POLICY posts_by_author ON posts
    USING (author_id = current_setting('app.caller_user_id', true)::uuid);
```

That is all a policy should decide. Whether a caller is an administrator, and what they may do,
is a rule about the application and belongs in the use case, never in a policy: a policy that
reads a role is authorization done in SQL, where it cannot be tested with the rest of the
domain. The application's side is to make sure `app.caller_user_id` is set for the tenant before
any statement in the transaction runs. That is what ``PostgresSettings`` are for.

## Settings are transaction-local

``PostgresDatabase`` applies every setting with `set_config(name, value, true)`. The `true`
makes the setting local to the transaction: visible to every statement inside it, and discarded
when it ends, by commit or by rollback. A pooled connection therefore never carries one caller's
settings into the next caller's transaction, whatever happened to the task that held it.

## Where the tenant is bound

The tenant is known where a request enters the process. That layer binds the setting into the
task's `ServiceContext`, beside whatever identity it already binds there, and every transaction
begun under that task reads it:

```swift
var context = ServiceContext.current ?? .topLevel
context.postgresSettings = ["app.caller_user_id": caller.id.uuidString.lowercased()]
return try await ServiceContext.withValue(context) {
    try await next(request, context)
}
```

Constant settings, such as `application_name`, are given to the database when it is built.
Settings from the context are applied over them.

## Nothing bound means nothing applied

A transaction begun with no settings in the context runs with only the constants. Under a policy
like the one above that read returns no rows rather than failing. Write policies so that an
unbound tenant sees nothing, and keep one integration test in each service that asserts exactly
that.

Work that must see every tenant, an administrator's report, a job run by another service, does
not bind a tenant and does not run through the policed role at all: it connects as a role whose
policy is `USING (true)`, and the use case that owns it names the tenant it means in its own
`WHERE` clause.
