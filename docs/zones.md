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
