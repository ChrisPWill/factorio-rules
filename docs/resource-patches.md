# Resource patch identity

`lib.resource_patches` maintains a persistent connected-component cache for resource
entities. Solid resources of the same prototype and surface join when their tiles
touch orthogonally or diagonally. Each patch records a stable generated ID, member
count, total sampled amount, and bounds.

Newly discovered resources inspect only their eight neighboring cache cells. When a
later chunk connects two known components, the older ID remains canonical and the
merged ID remains as a resolvable alias. Reconstructing the tracker around the same
stored state preserves IDs across save and load; placement checks query the cache and
do not scan the map.

Fluid resources such as crude-oil wells use one patch per resource entity. They do
not join adjacent wells, because their discrete placement and yield semantics differ
from tile-based solid deposits. Resource names and surfaces always form separate
patches.
