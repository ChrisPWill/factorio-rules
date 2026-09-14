# Extension API

Other mods may add declarative rule behavior through the `factorio_rules` remote
interface. Predicate and action names must be globally namespaced (`mod:name`).

`register_predicate_provider(name, descriptor, requirements)` and
`register_action_provider(name, descriptor, requirements)` take a data-only
descriptor: `{ interface = "other-mod", function_name = "predicate" }`. The
named function must already be exposed by the other mod's remote interface.
It receives normalized serializable context and condition/action data; it never
receives persistent storage or evaluator internals. UI and import data cannot
register providers.

Rules themselves use the registry operations `register_rule`, `replace_rule`,
`override_rule`, and `replace_external_rule`; IDs remain globally namespaced.
The UI and imported text paths accept data only and cannot inject executable
callbacks.
