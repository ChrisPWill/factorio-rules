# Rule registry

`lib.rules.registry` is the sole owner of rule resolution. Persisted state keeps
source entries, ordered patches, sparse save overrides, diagnostics, and source
and override versions. It does not persist an effective-rule cache.

On initialization and configuration changes, `sync_source(source, rules)`
replaces the current code-owned definitions for that source. Rules with
`provenance.kind = "save"` are retained, even when they share a namespace with
the source. Sparse overrides remain after a source disappears; effective-rule
inspection reports them as orphaned and applies them again if the source returns.

`effective()` returns detached snapshots and warnings without changing saved
state. A write-capable lifecycle owner records diagnostics after a successful
configuration. Patches may declare an integer order; ties use their persisted
sequence. Effective provenance contains full rule lineage and the latest owner
of each changed top-level field.
