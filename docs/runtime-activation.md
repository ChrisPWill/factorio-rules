# Runtime activation

`runtime.subscriptions` turns the compiler's required event list into registered
handlers. Event definitions provide a registration function and may provide
filters. Dynamic subscriptions are removed when no active rule needs them;
low-frequency definitions can set `dynamic = false` and remain registered. A
failed rebuild leaves the existing registrations in place, and equal effective
configuration is a no-op.

`runtime.rule_validation` checks active rules against available event, predicate,
and action registries before evaluation. Missing references disable the affected
rule and emit a warning by default. Set `rule.validation.<reference> = "error"`,
or provide a severity callback/table, when an unavailable reference should reject
the activation update instead. Validation returns the filtered active rule set,
diagnostics, and fatal errors separately so callers can report warnings without
starting an invalid runtime.
