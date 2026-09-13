# Agent rules

1. Use Jujutsu (`jj`) for source control. Try the equivalent `jj` command before
   falling back to Git, and use Git only when `jj` cannot perform the operation.
2. Keep each task in its own Jujutsu change. Run `jj new` before starting unrelated
   work and after describing or pushing a change before making further edits.
3. Keep Jira issue statuses aligned with actual progress: mark work in progress
   when it starts and done only after its acceptance criteria are verified.
4. Run `make all-checks` before marking implementation work done. This includes
   Nix checks, unit tests, generated Factorio tests, and the player-GUI fixture.
5. Factorio behavior changes need integration coverage through the real
   application boundary and registered handlers. Do not rely only on isolated
   helpers or unsupported synthetic GUI/construction events.
6. Route save-owned rule mutations through `mutate_rules`. Preserve revision
   checks, source ownership, and atomic failure behavior; UI code must not write
   registry state directly.
7. Keep `tests/fixtures/gui-test-fixture.zip` minimal and free of personal or
   factory data. Update its checksum and setup documentation whenever it changes.
8. When changing the pinned Factorio version, update the download checksum, CI,
   documentation, cache examples, and run the full integration suite together.

## Software design

1. Design deep modules: give callers a small, clear interface and hide internal
   complexity and data representation.
2. Keep each important concept and invariant in one owner. Reuse that owner
   rather than duplicating matching, validation, state-layout, or lifecycle logic.
3. Prefer straightforward, general-purpose interfaces over special-case wrappers
   and pass-through abstractions.
4. Preserve behavior with focused regression tests before simplifying code;
   prefer deletion and consolidation over adding layers.
5. Write comments for design intent, constraints, and tradeoffs. Do not narrate
   code that already states what it does.
