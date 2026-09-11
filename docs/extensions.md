# Extension API

Other mods may add declarative rule behavior through the `factorio_rules` remote
interface. Predicate and action names must be globally namespaced (`mod:name`).

`register_predicate(name, callback, requirements)` calls the callback with the
normalized rule context, its condition data, and a constrained services table.
`register_action(name, callback, requirements)` registers a secondary effect
handler invoked after a warning or denial with the action data, violation record,
context, and construction boundary. These callbacks do not receive persistent
storage or the evaluator internals.

Rules themselves use the registry operations `register_rule`, `replace_rule`,
`override_rule`, and `replace_external_rule`; IDs remain globally namespaced.
The UI and imported text paths accept data only and cannot inject executable
callbacks.
