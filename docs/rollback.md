# Construction rollback

Denied construction is reverted after the pure evaluator returns `deny`, because
Factorio build events occur after placement. `runtime.rollback` captures the
temporary `consumed_items` inventory and spill location before destroying the
entity. It then inserts the consumed stacks into the responsible player or robot
inventory and spills only any remainder on the original surface.

The consumed inventory preserves the item and quality actually used for ordinary
player and robot builds. Ghost and script-raised paths normally consume no item, so
their rollback removes the invalid entity without inventing a refund. A second
rollback of the same event sees an invalid entity and performs no mutation.

Failures are reported with the unreturned item count. A failed entity destruction
never starts refunding, which prevents duplication; insert failures fall back to a
ground spill so full inventories and cursors do not silently lose items.
