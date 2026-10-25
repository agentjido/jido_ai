# Anatomy of an AI turn

One routed AI turn has these steps:

1. Core Jido selects the route and prepares Plugin input.
2. `Jido.AI.Turn.prepare/2` validates the current Session or Thread.
3. Jido AI prepares the model, messages, visible tools, output contract, and
   limits.
4. The input control runs.
5. The configured reasoning Flow runs model and tool work.
6. The output control checks the final output.
7. The reasoning Flow returns a completed `Jido.AI.Result`.
8. `Jido.AI.Turn.complete/4` validates the route reply data and builds route
   output.
9. Core Jido projects and commits the candidate state.
10. Core Jido builds and delivers the correlated Reply Directive after commit.

```text
Signal -> prepare -> input control -> reasoning Flow -> output control
       -> completed result -> candidate state and reply -> core commit
```

An error before step 8 does not change Agent state. An error during Directive
delivery does not repeat model or tool work.

Direct `generate/2`, `reason/2`, and `run/2` calls stop after the AI result.
They do not build or commit Agent state.

Use `preflight/2` to inspect step 3 without running later steps.
