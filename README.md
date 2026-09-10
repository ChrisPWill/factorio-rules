# Factorio Rules

A configurable rules mod for Factorio **2.0**. This repository currently contains
the development foundation; gameplay rules will follow in separate stories.

## Build and install

Run `make package` with Python 3 and Make installed. Copy
`dist/factorio-rules_0.1.0.zip` into your Factorio mods directory and enable it.
The package includes only `mod/` files, with sorted entries, fixed timestamps and
permissions, and no compression so identical inputs produce identical zip bytes.
Run `make validate` to check metadata and entry points independently.

## Development tools

Run `nix flake check` for the same validation gate used by GitHub Actions. It
checks metadata, formatting, static analysis, unit tests, packaging behavior, and
the workflow itself. `nix build` creates a `result` link containing the reproducible
mod zip. Both commands reuse the Nix store, so running one after the other does not
repeat the build.

Run `make all-checks` to include the real Factorio integration scenario. On its
first run, the command downloads Factorio headless 2.0.60, verifies its SHA-256
digest, and extracts it under the gitignored `.cache/factorio/` directory. Later
runs reuse that download and binary.

Run `nix develop` to enter the pinned development environment. Inside it, `make
lint` runs Lua 5.2 formatting and static analysis, `make test` runs unit tests, and
`make format` applies formatting.
Without Nix, install Lua 5.2, StyLua, Luacheck, Python 3 and Make.
Checks target source directories explicitly and exclude generated and vendor files.
GitHub Actions runs the same lint command for pull requests and pushes to `main`.

## Module boundaries

- `mod/settings.lua` defines configuration prototypes.
- `mod/data.lua` owns data-stage prototype definitions.
- `mod/control.lua` registers runtime lifecycle handlers; `mod/runtime/` owns
  Factorio runtime interactions.
- Future `mod/lib/` modules must be pure Lua: no Factorio globals, so rule and
  geometry logic can run in unit tests without the game.

Persistent data belongs under `storage.rules`. Its `schema_version` starts at 1;
future migrations must preserve saved user data. Initialize storage only during
`on_init` and `on_configuration_changed`; never write it during `on_load`.
Enable the **Debug logging** runtime setting for prefixed messages in the game log.

See Factorio's [mod structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
and [storage lifecycle](https://lua-api.factorio.com/latest/auxiliary/storage.html)
documentation. Source control uses `jj`; see [AGENTS.md](AGENTS.md).

## Unit tests

Run `make test` in `nix develop`, or `nix develop --command make check` for all
validation, lint and unit checks. Files matching `tests/unit/*_spec.lua` are
discovered automatically. Each spec returns an array of `{name = "...", run =
function() ... end}` cases and uses Lua's `assert` for expectations. Use a loop
over input/expected tables to add cases, as in `tests/unit/lifecycle_spec.lua`.
The runner adds `mod/` to `package.path`, so future pure rule/geometry modules can
be loaded with `require("lib.module")` without Factorio. Runtime modules can be
loaded into an explicit fake environment using Lua 5.2 `loadfile`.

Failures print a traceback, continue remaining cases, and return a nonzero exit
status. Empty suites and malformed specs also fail. Python tests verify that
failure contract and reproducible packaging.

## Factorio integration tests

Set `FACTORIO_BIN` to a Factorio 2.0 headless executable and run `make
integration-test`. The command packages the current mod, creates an isolated mod
directory, starts the `factorio-rules/integration` scenario, captures the complete
Factorio log, and requires both a successful process and the final success marker.

Add cases to `mod/scenarios/integration/control.lua`. Each case receives a real
Factorio surface and can place entities and inspect their results. Failed assertions
raise a runtime error, make Factorio exit unsuccessfully, and remain visible in the
captured log. Temporary saves and mod state are removed after each run.

## Continuous integration

Pull requests and pushes to `main` run `nix flake check`, build the same flake
package, and run the Factorio 2.0.60 headless scenario. The headless
download is checked against its published SHA-256 digest. Successful runs publish
`factorio-rules_0.1.0.zip` as the `factorio-rules` workflow artifact.

The integration scenario stays separate because Factorio is downloaded outside
Nix and cannot run in the pure, network-isolated `nix flake check` build. Run it
locally with `FACTORIO_BIN=/path/to/factorio make integration-test` when a compatible
headless binary is available.
