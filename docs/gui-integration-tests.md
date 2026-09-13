# Headless GUI integration tests

Factorio 2.0.77 can use GUI objects belonging to a player already stored in a save,
without a client connected. The engine does not expose `game.create_player`.

Run all checks, including the GUI suite:

```sh
make all-checks
```

The command downloads/verifies the pinned headless binary if needed, runs the usual
Nix and generated-scenario checks, then loads a temporary copy of the checked-in
player fixture for GUI tests. The fixture and its checksum are required: a missing
or altered fixture fails the command and CI.
To run only the GUI suite with an already available binary:

```sh
FACTORIO_BIN=".cache/factorio/2.0.77/factorio/bin/x64/factorio" \
FACTORIO_PLAYER_SAVE="tests/fixtures/gui-test-fixture.zip" make integration-test
```

`tests/fixtures/gui-test-fixture.zip` was created in Factorio 2.0.77 as a minimal
Freeplay save on Nauvis, using seed `3885402781`, with enemies disabled and only the
official `base`, `space-age`, `quality`, and `elevated-rails` mods. It contains one
player with a character and cursor inventory, no factory, and no personal game data.
Its SHA-256 is recorded in `tests/fixtures/gui-test-fixture.sha256`.

The test server disables public/LAN advertising and auto-pause. It works exclusively
on temporary save/mod copies, including any save made on server shutdown; the
checked-in source fixture is never modified. Set `FACTORIO_PLAYER_SAVE` to a separate
compatible save only when testing that save deliberately.

The harness adds a temporary test mod, triggering configuration-change initialization
of the real mod, and injects a test-only event driver into the temporary package.
Factorio does not permit `raise_event` for GUI or player/robot construction events.
The driver invokes the mod's actual registered handlers, with real LuaGuiElement
objects; the headless suite also uses real script-raised construction events.
The distributable archive remains unchanged by this instrumentation.

The GUI suite opens the manager, renames a zone, redraws it with the same ID and
removes it through unused-zone cleanup. The separate generated scenario suite
checks enforcement and does not require a player. Distinct success markers prevent
one suite's completion from masking failure of the other.

This verifies runtime API use and event routing, not visual layout or mouse input.
Save/load without a configuration change remains part of KAN-36.
