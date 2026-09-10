# Canonical rule schema v1

Rules are plain serializable Lua tables. They contain no callbacks or Factorio
objects, so the same definitions can be persisted, edited by a future UI, exported,
or registered by another mod. `lib.rules.schema.normalize` copies and validates a
definition and returns either the canonical rule or a list of errors with field paths.

```lua
{
  schema_version = 1,
  definition_version = 1,
  id = "factorio-rules:nauvis-spawn-miners",
  enabled = true,
  priority = 100,
  provenance = { source = "factorio-rules", kind = "builtin" },
  event = { domain = "construction", kind = "entity-built" },
  selector = { entity_types = { "mining-drill" } },
  scope = { surfaces = { "nauvis" } },
  when = {
    all = {
      { predicate = "entity.is-mining-drill" },
      { predicate = "entity.in-spawn-resource-zone" },
    },
  },
  effects = {
    primary = {
      type = "deny",
      reason = "Mining drills are not allowed in the spawn resource zone.",
    },
    actions = {
      { type = "factorio-rules:notify-player", severity = "error" },
    },
  },
}
```

IDs use `mod-name:rule-name` so independently registered rules cannot collide.
`schema_version` selects this repository's data shape. `definition_version` belongs
to the individual rule and changes when its meaning changes. `enabled` defaults to
true and integer `priority` defaults to zero.

`event` selects a domain and event kind. `selector` cheaply narrows candidates;
`scope` describes where or to whom the rule applies. Their domain-specific fields
remain data so new domains do not require a schema callback mechanism.

Conditions use exactly one of `all`, `any`, `not`, or `predicate`. An `unless`
condition is accepted at the authoring boundary and normalized into `not`; when
`when` is also present the canonical condition becomes `when AND NOT unless`.

Rules are restrictions. If no enabled rule matches, the action is allowed. A
matching `deny` primary outcome denies it. A matching `warn` outcome allows it with
feedback. Priority controls deterministic evaluation order and which matching reason
is surfaced; it never turns an allow or warning into an override for a denial.

Every effect has one primary outcome and zero or more secondary actions. Secondary
action types are namespaced strings whose implementations are supplied by runtime
code. The canonical definition stores only their configuration data.
