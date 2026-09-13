# Construction authoring catalogue

`lib.rules.catalogue` owns the data-only descriptions and validation used by future
UI and import commands. `describe()` supplies fields, predicates, effects, templates
and bounds. A predicate is available only when the caller supplies its actual
runtime handler. Zone templates remain unavailable until generic zone evaluation
is implemented. Existing extension rules without descriptors remain inspectable;
validation refuses to edit them rather than dropping unknown fields.

`validate(rule)` normalizes through the canonical schema, checks compatible events,
parameters, selectors, scope and references, and returns field-path errors without
changing the input. Reference resolution is injected; runtime validation checks
Factorio prototypes, surfaces, forces and registered zones. Descriptor parameters
use string/boolean/number/integer types, optional required/min/max/values constraints
and reference kinds. Extensions may supply descriptors to the catalogue constructor;
this does not register their runtime handlers.

`template(id, config)` returns a canonical rule or errors. Supported templates are
surface-ban, protected-zone, required-zone, warning and spawn-miners. IDs/provenance
from this draft API are placeholders; authoritative allocation belongs to the
future transactional command boundary. No template is applied to the save here.

Conditions must be nonempty, at most eight levels deep and 64 nodes total. These
bounds live in the canonical schema so all configuration paths share them.
Authorable priority is an integer from -1,000,000 to 1,000,000 and violation messages
are nonempty strings of at most 500 bytes. Feedback currently goes to the actor or
force automatically; no configurable notification action is advertised without a
handler. Entity and scope choices use names; unknown names are validation errors.

Rules restrict construction. Warnings allow it; denials reject it. Priority selects
the reported reason among matching rules and never makes a warning override a denial.

The remote interface exposes `authoring_catalogue()` and
`validate_authored_rule(rule)` for data-only inspection and validation.

## Save-owned transactions

`mutate_rules(commands)` is the single write boundary for save-owned construction
rules. A command has a `kind`, a target `id` where applicable, and the current
`revision`. It supports `create`, `update`, `duplicate`, `set-enabled`,
`set-priority`, `delete`, and `reset`. Create and duplicate allocate stable
`factorio-rules:rule-N` IDs and record `provenance.kind = "save"`; callers cannot
choose either value. Source-owned rules allow only the sparse enabled/priority
overrides and reset, while save-owned rules can be replaced or deleted.

A request is an all-or-nothing batch. The boundary copies persisted state, applies
every command, normalizes and catalogue-validates authored rules, verifies a staged
compiler, and only then replaces saved state. The application rebuilds active policy
after a successful transaction. Errors are returned
as `{ field, message }` diagnostics, so a rejected request leaves rules, overrides,
compiled enforcement and zone references unchanged. Selectors, scopes, conditions,
effects and zone lists are replacement fields, which prevents stale entries from a
previous edit surviving a shorter replacement.

The manager supplies the revision and player index from the server-side GUI event;
it does not treat GUI element tags as authority. KAN-37 will apply multiplayer
permission policy at this context boundary.
