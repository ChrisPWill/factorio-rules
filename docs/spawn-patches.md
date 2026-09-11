# Spawn resource classification

Spawn patches are the solid resource cells discovered during an explicit initial
window for a surface and force. The discovery scheduler opens the window, records
patch IDs found in the initial spawn area, and closes it after that bounded work is
complete. Classification is maintained separately for every force.

Closing a window copies the currently known member cells into a persistent lookup.
That snapshot is immutable: deposits discovered later remain non-spawn even when
new resource cells connect them to a classified patch. Ordinary placement checks
query this lookup by surface, resource prototype, and tile without searching the
map.

Fluid resources are recorded as excluded during the window and always return a
specific unsupported result. This first classifier does not infer spawn status for
oil wells. An unopened or still-open window is also reported as incomplete instead
of guessing.
