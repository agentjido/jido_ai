# Reasoning Internals

Jido AI does not use public Strategy wrapper modules. A profile selects a
reasoning method. The shared runtime prepares and executes that method.

```text
Jido.AI.Agent DSL
  -> Jido.AI.Profile
  -> Jido.AI.Authoring.lower/2
  -> core Jido.Agent routes and plugins
  -> Jido.AI.Orchestration request runtime
  -> Jido.AI.Runtime.Flow
  -> Jido.AI.Reasoning method functions
```

## Public Method Namespaces

The public reasoning namespaces provide stable method values, prompts, result
inspection, and result helpers. They do not implement a second Agent execution
contract.

- `Jido.AI.Reasoning.ChainOfDraft`
- `Jido.AI.Reasoning.ChainOfThought`
- `Jido.AI.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Reasoning.TreeOfThoughts`
- `Jido.AI.Reasoning.GraphOfThoughts`
- `Jido.AI.Reasoning.TRM`
- `Jido.AI.Reasoning.Adaptive`
- `Jido.AI.Reasoning.ReAct`

Use each namespace's `method/0` value in an inert profile. Use the shared
`ask`, `ask_sync`, `ask_stream`, `await`, `cancel`, and `steer` Agent API for
runtime requests.

## Runtime Engines

Linear methods parse one model result. Algorithm, tree, graph, and recursive
methods keep private machine data that supports the shared Flow. These machine
modules are implementation details. They do not define Agent routes or worker
messages.

ReAct also has a standalone runtime. It uses the same canonical
`Jido.AI.Runtime.Event` values and supports checkpoint tokens. The standalone
runtime is separate from Agent authoring.

## Extension Rules

- Add public configuration to `Jido.AI.Profile` and the Spark DSL.
- Keep profile construction free of model and tool calls.
- Put shared request execution in `Jido.AI.Orchestration` and `Jido.AI.Runtime`.
- Put method-specific preparation, parsing, and advancement in
  `Jido.AI.Reasoning`.
- Do not add a method-specific Agent macro or Strategy wrapper.
