# Headless GUI integration tests

Factorio 2.0.60 can use GUI objects belonging to a player already stored in a save,
without a client connected. The engine does not expose `game.create_player`.

Run all checks, including the GUI suite, with a compatible save:

```sh
FACTORIO_PLAYER_SAVE="/path/to/save.zip" make all-checks
```

The command downloads/verifies the pinned headless binary if needed, runs the usual
Nix and scenario checks, then loads a temporary copy of the save for GUI tests.
Without `FACTORIO_PLAYER_SAVE`, it explicitly reports that GUI tests were not run.
To run only the GUI suite with an already available binary:

```sh
FACTORIO_BIN=".cache/factorio/2.0.60/factorio/bin/x64/factorio" \
FACTORIO_PLAYER_SAVE="/path/to/save.zip" make integration-test
```

Use a Factorio 2.0.60-compatible save with at least one player and a cursor inventory.
Newer saves cannot necessarily be loaded by the pinned binary. A small vanilla save
with a character on Nauvis is preferred. A missing player makes the GUI suite fail;
it never silently skips the tests. The test server disables public/LAN advertising
and auto-pause. It works exclusively on temporary save/mod copies, including any
save made on server shutdown. Personal saves are not committed or uploaded.

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
Save/load without a configuration change remains part of KAN-36. A minimal,
redistributable player fixture is still needed before GUI tests can run in CI.
