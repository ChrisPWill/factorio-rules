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
