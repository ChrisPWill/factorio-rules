# Factorio Rules

A configurable rules mod for Factorio **2.0**. This repository currently contains
the development foundation; gameplay rules will follow in separate stories.

## Build and install

Run `make package` with Python 3 and Make installed. Copy
`dist/factorio-rules_0.1.0.zip` into your Factorio mods directory and enable it.
The package includes only `mod/` files, with sorted entries, fixed timestamps and
permissions, and no compression so identical inputs produce identical zip bytes.
Run `make validate` to check metadata and entry points independently.

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
