# Spawn resource classification

Spawn patches are the solid resource cells discovered during an explicit initial
window for a surface and force. The discovery scheduler opens the window, records
patch IDs that overlap the initial 128-tile circle around the force spawn, and
closes it after that bounded work is complete. Classification is maintained
separately for every force. This fixed discovery boundary is independent of the
configurable enforcement radius, so loading additional nearby chunks cannot turn
their deposits into spawn patches.

Closing a window copies the currently known member cells into a persistent lookup.
That snapshot is immutable: deposits discovered later remain non-spawn even when
new resource cells connect them to a classified patch. Ordinary placement checks
query this lookup by surface, resource prototype, and tile without searching the
map.

Fluid resources are recorded as excluded during the window and always return a
specific unsupported result. This first classifier does not infer spawn status for
oil wells. An unopened or still-open window is also reported as incomplete instead
of guessing.
