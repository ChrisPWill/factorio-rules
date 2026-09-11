# Nauvis spawn-area miner rule

The built-in `factorio-rules:nauvis-spawn-miners` rule denies mining-drill
construction on Nauvis inside the force-relative spawn circle unless the drill's
mining area overlaps a solid resource cell frozen by initial spawn discovery. The
radius is controlled by **Nauvis spawn mining restriction radius** and defaults to
500 tiles.

Player, robot, blueprint ghost, revived ghost, and cooperating script builds enter
the same construction evaluator. A denial uses the shared rollback/refund path and
emits feedback containing the rule ID and reason. While initial classification is
still incomplete, the spawn-patch predicate fails open to avoid rejecting a valid
spawn-patch drill before the bounded discovery queue finishes.

The overlay controller renders the same force-spawn circle used by evaluation. Its
shortcut remains a per-player presentation preference and has no effect on policy.
Changing the radius rebuilds the compiled zone and overlay geometry without changing
the frozen spawn-resource classification.
