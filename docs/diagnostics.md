# Feedback and diagnostics

Every denial and warning can emit a player-facing message containing the selected
rule ID and reason. Player construction targets that player; robot and script-raised
construction targets the affected force. Feedback runs independently of rollback,
and secondary action intents are dispatched there so later sound or map-ping actions
do not become rollback responsibilities.

Normal evaluation returns only the outcome, selected rule and reason, ordered
matched rule IDs, and secondary action intents. Pass `{ explain = true }` to the
evaluator only for an explicit diagnostic request; this adds per-rule selection and
condition traces.

The runtime-global **Recent violation history size** setting controls compact
history in `storage.violations`. It defaults to 20 entries, is capped at 200, and
may be set to 0 to disable history. Entries contain normalized context data and
never retain Factorio objects or full explanation trees.
