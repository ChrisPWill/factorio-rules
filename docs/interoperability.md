# Construction interoperability

Factorio Rules handles `script_raised_built` and `script_raised_revive` through the
same context, evaluator, and enforcement path as player and robot construction.
Mods should set `raise_built = true` when creating an entity so Factorio emits the
corresponding event.

Construction performed by `LuaSurface.create_entity` without `raise_built = true`
is not observable by other mods. A cooperating mod can submit such an entity after
creation:

```lua
remote.call("factorio_rules", "enforce_construction", entity)
```

The optional second argument may be `"script_raised_built"` or
`"script_raised_revive"`. Repeated submissions for the same entity and tick are
evaluated once, so a mod can use the interface alongside raised events safely.

The interface only submits a construction event. It does not register rules,
predicates, effects, or policy overrides. Map generation and scenario setup that do
not emit construction events remain outside the observable construction boundary.
