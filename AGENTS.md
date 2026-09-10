# Agent rules

1. Use Jujutsu (`jj`) for source control. Try the equivalent `jj` command before
   falling back to Git, and use Git only when `jj` cannot perform the operation.
2. Keep each task in its own Jujutsu change. Run `jj new` before starting unrelated
   work and after describing or pushing a change before making further edits.
3. Keep Jira issue statuses aligned with actual progress: mark work in progress
   when it starts and done only after its acceptance criteria are verified.
