# Actions Catalog

This guide is the quick inventory of built-in `Jido.AI.Actions.*` modules and what each one is for.

## LLM Actions

- `Jido.AI.Actions.LLM.Chat`
  - Chat-style generation with optional system prompt.
- `Jido.AI.Actions.LLM.Complete`
  - Simple text completion.
- `Jido.AI.Actions.LLM.Embed`
  - Embedding generation for one or many texts.
- `Jido.AI.Actions.LLM.GenerateObject`
  - Structured object generation constrained by schema.

## Tool Calling Actions

- `Jido.AI.Actions.ToolCalling.CallWithTools`
  - LLM call with tool schema exposure and optional auto-execution loop.
- `Jido.AI.Actions.ToolCalling.ExecuteTool`
  - Execute a tool by name through `Jido.AI.Turn`.
- `Jido.AI.Actions.ToolCalling.ListTools`
  - Enumerate available tools and optional schemas.

## Streaming Actions

- `Jido.AI.Actions.Streaming.StartStream`
  - Start streaming and register lifecycle state.
- `Jido.AI.Actions.Streaming.ProcessTokens`
  - Consume stream chunks with optional callbacks/transforms.
- `Jido.AI.Actions.Streaming.EndStream`
  - Finalize stream and return usage/result metadata.

## Reasoning Actions

- `Jido.AI.Actions.Reasoning.Analyze`
  - Structured analysis by analysis type.
- `Jido.AI.Actions.Reasoning.Infer`
  - Logical inference from premises and question.
- `Jido.AI.Actions.Reasoning.Explain`
  - Explanations with detail-level targeting.

## Planning Actions

- `Jido.AI.Actions.Planning.Plan`
  - Goal-to-step plan generation.
- `Jido.AI.Actions.Planning.Decompose`
  - Hierarchical goal decomposition.
- `Jido.AI.Actions.Planning.Prioritize`
  - Task prioritization under criteria/context.

## Shared Helper

- `Jido.AI.Actions.Helpers`
  - model resolution, security/input checks, response text/usage extraction.

## Selection Heuristic

- Need raw chat/completion/embed/object: use LLM actions.
- Need model-selected tools: use Tool Calling actions + `ToolAdapter`.
- Need progressive output: use Streaming actions.
- Need domain reasoning/planning templates: use Reasoning/Planning actions.

## Failure Mode: Action Used Outside Expected Context

Symptom:
- runtime errors due to missing `context[:tools]` or missing provider config

Fix:
- pass required context explicitly
- verify model/provider config and tool maps before execution

## Next

- [Plugins And Actions Composition](plugins_and_actions_composition.md)
- [Tool Calling With Actions](../user/tool_calling_with_actions.md)
- [Configuration Reference](configuration_reference.md)
