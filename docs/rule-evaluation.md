# Rule evaluation

`lib.rules.evaluator` evaluates normalized rules in descending numeric priority,
using the rule ID as a stable tie-breaker. Event, selector and scope checks reject
irrelevant rules before predicate evaluation. Predicates receive only RuleContext
and condition data; mutation and raw Factorio objects are outside this module.

No match returns `allow`. Matching warnings return `warn` and feedback intents.
Any matching denial returns `deny`, even when a warning has higher priority. Priority
selects the first reason within the winning outcome and never acts as an implicit
policy override. Results contain ordered matched rule IDs and secondary action data;
another runtime layer applies mutations and effects.

`lib.rules.compiler` snapshots active definitions and indexes them by event, entity
type and name, source, surface, and force. Call `replace` after registrations or
configuration change, then pass `candidates(context)` to the evaluator. Replacing
the compiler with an equal definition set is a no-op; `revision()` changes only
when the compiled snapshot changes.

The compiler also reports sorted `domains`, `events`, `capabilities`, and `services`
from `requirements()`. Predicate and action implementations declare their static
requirements when the compiler is created. A declaration may instead be a function
of the condition or action data when the requirement is configured by the rule.
Disabled rules contribute neither candidates nor requirements.

The normal path allocates no explanation tree. Pass `{ explain = true }` as the
third evaluation option to receive per-rule selection state and a complete condition
tree. This is intended for explicit diagnostics rather than persistence or routine
event handling.
