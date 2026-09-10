# Normalized rule context

Every rule evaluation receives one common envelope plus a payload owned by its
event domain. The common fields are `domain`, `kind`, `surface`, optional `force`
and `actor`, and cheap event `metadata`. A construction payload can contain source,
entity identity, type, position and other values copied by its adapter.

`lib.rules.context.new` rejects functions, userdata, threads, cycles and non-finite
numbers in normalized data. Factorio event objects and `LuaEntity` instances must
stay in the adapter or extension boundary; built-in predicates consume normalized
fields instead.

Expensive derived state is requested explicitly through
`context:get_capability(name)`. The resolver is not called until requested, and
each result is cached for that context. The capability registry and providers are
implemented separately so contexts do not eagerly copy resource patches, zone
membership, production statistics or other derived state.
