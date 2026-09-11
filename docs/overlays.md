# Zone overlays

The **Toggle rule-zone overlays** shortcut controls a persistent preference for each
player. Rule-specific visibility preferences are stored separately, so multiplayer
players may choose different presentations of the same authoritative zones.

`runtime.overlays` renders resolved circle and rectangle presentations on their
specified surfaces. It caches one rendering object per stable presentation key and
updates the object's player audience when preferences change. Geometry changes
replace the affected object; ordinary toggles do not recreate it.

Rules may mark an overlay as forced when defining its presentation. An admin may
also force a zone through the controller API. Forced visibility is explicit and
bypasses personal hiding, while all other overlay state remains presentation-only:
it does not mutate rule definitions or reusable zone geometry.
