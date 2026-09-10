# Capability providers

`runtime.capabilities` connects the capabilities declared by compiled rules to
runtime state. Register one or more providers for a capability, then call
`apply_requirements(compiler:requirements().capabilities)` whenever the compiled
rule revision changes. Contexts use the same resolver through `get_capability`.

Providers are selected in this order: native Factorio query, Factorio statistics,
then a maintained tracker. The entity-count helper calls
`LuaSurface.count_entities_filtered` at resolution time. The production-total
helper reads `LuaFlowStatistics`; its injected statistics lookup chooses the force
and surface scope required by the capability.

Tracker providers own `activate` and `deactivate` callbacks. These callbacks should
subscribe and unsubscribe any high-frequency events used only by that tracker.
Applying unchanged demand is idempotent, and removing the final requirement calls
`deactivate`. Missing providers reject the whole demand update, leaving the prior
active set intact.
