# Incremental resource discovery

Chunk generation enqueues resource discovery work by surface and chunk. A bounded
number of queued chunks is scanned per tick, and the tick handler is removed when
the queue drains. Duplicate and already-processed chunks are ignored. This is an
event-driven worker for patch discovery rather than a general polling loop.

Placement checks call the patch tracker's cell cache directly. They never invoke a
surface resource search. The persistent queue and processed-chunk set survive saves,
so interrupted work resumes without scanning completed chunks again.

After startup discovery drains, the configured expected resource prototypes are
compared with discovered patches. Missing resources produce warnings and no synthetic
patches. The **Expected Nauvis spawn resources** runtime setting is a comma-separated
list and may be blank when a mod pack has different generation assumptions.

An explicit rebuild clears the patch and spawn-classification caches, clears the
processed-chunk set, and queues every supplied generated chunk again. Ordinary load,
configuration change, placement, and new chunk discovery do not rebuild the cache.
