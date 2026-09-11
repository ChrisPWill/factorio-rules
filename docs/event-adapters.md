# Event-domain adapters

`runtime.adapters.registry` maps a Factorio event source to a small adapter. An
adapter returns a normalized RuleContext specification and a separate raw boundary.
Only adapter and extension code may use the boundary; the core evaluator receives
the context alone.

The construction adapter maps player, robot, script-raised build and script-raised
revive events to `construction/entity-built`. All expose the same normalized entity
identity, position, surface, force and actor shape. Raw events, entities, temporary
inventories and robots remain in the boundary for later rollback and compatibility
effects.

Construction enforcement evaluates entity ghosts by their target `ghost_name` and
`ghost_type` by default, so blueprint placement cannot bypass rules that select the
completed entity. A runtime may explicitly choose the `ignore` ghost policy when it
wants to defer rejection until revive or completion; completed entities are always
evaluated. Invalid or already-destroyed ghosts are ignored at the event boundary.

Runtime subscription code owns the mapping from `defines.events` IDs to the source
strings registered here. To add another domain, register another source adapter that
produces a RuleContext specification; no evaluator change is required.
