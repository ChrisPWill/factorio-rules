# Zones

`lib.zones` stores reusable, serializable zone definitions in a simple ID map. A
zone has a stable namespaced ID, a circle or centered rectangle shape, an absolute
coordinate or force-spawn anchor, and optional surface and force scope.

```lua
{
  id = "factorio-rules:nauvis-spawn",
  shape = { type = "circle", radius = 64 },
  anchor = { type = "force-spawn" },
  scope = { surfaces = { "nauvis" }, forces = { "player" } },
}
```

Circle membership compares squared distances and rectangle membership compares
axis distances against half-width and half-height. Boundary points are inside.
Lookup remains a direct ID lookup; no spatial tree is maintained.

Zone scope selects the relevant surface and force. Player or actor applicability
belongs in rule scope and is not part of zone geometry. Definitions contain no
rendering IDs or Factorio objects, so multiple rules and the overlay layer can use
the same zones independently.

Admins can use the **Select rule zone** shortcut to put a selection tool in the
cursor, drag a rectangle in the world or map, and persist an absolute rectangle
scoped to the current surface and force. The selection uses the normal zone and
overlay paths; arbitrary polygons are not supported.

## Named zones and rule conditions

Custom zones have stable IDs and optional display names. In Manage rules, rename a
zone by editing its name and pressing Enter. Redraw puts the selection tool in the
cursor; drawing on the same surface and force replaces geometry under the same ID.
The standalone selection shortcut still creates a new zone.

Construction rules can use `{predicate="factorio-rules:inside-zone", zone_id=id}`
in any condition. Boundaries include the edge and use the entity/ghost position.
Before evaluating the condition, the application checks that every referenced zone
exists and applies to the event's surface/force. This also guards negated conditions:
“not inside” never means “anywhere on an unrelated surface”. Missing zone references
disable runtime evaluation and produce a rule warning, preserving the definition.

References come from catalogue-declared zone parameters and the built-in spawn
predicate. Legacy `zone_ids` remain conservative retention references. Cleanup
examines source definitions, patches and save overrides, including disabled and
restorable rules. It never deletes the built-in spawn zone. External mods can use
`list_zones()` and `save_zone(definition)`; omit ID for creation and reuse it for edits.
