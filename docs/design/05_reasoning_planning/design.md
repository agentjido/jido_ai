> Target seam design. This document is pending approval.

# Reasoning and planning methods design

## Scope and owner

- Owner: Jido AI reasoning and planning method modules.
- In scope: Method identity, prompts, options, portable state, candidates, scores, search policy, limits, tool eligibility, completion rules, plan values, and method results.
- Out of scope: Provider calls, generic graph scheduling, worker pools, Agent lifecycle, durable plan execution, and application workflow semantics.

## V2 capability anchor

V2 included ReAct, Chain-of-Thought, Chain-of-Draft, Algorithm-of-Thoughts, Tree-of-Thoughts, Graph-of-Thoughts, TRM, Adaptive reasoning, and planning behavior. V3 keeps approved AI methods but expresses their execution through standard Actions and Flows.

| V2 capability | V3 target |
| --- | --- |
| Strategy module per method | Method specification plus Actions and Flow factory |
| Private machine state | Validated portable method state |
| Candidate worker fan-out | `Jido.Flow.Map` |
| Candidate evaluation and fold | Method score Action plus `Jido.Flow.Reduce` when serial |
| Method loop | Bounded `Jido.Flow.Iterate` or terminal continuation |
| Dynamic method choice | Adaptive policy plus `Jido.Flow.Dispatch` |
| Plan execution | Plan value only; Flow or host executes approved work |

## Model

Every public method implements one semantic behavior:

```elixir
@callback id() :: atom()
@callback option_schema() :: Zoi.schema()
@callback state_schema() :: Zoi.schema()
@callback capabilities() :: map()
@callback build(profile, opts) ::
  {:ok, Jido.Flow.t()} | {:error, Jido.AI.Error.t()}
@callback result(state) ::
  {:ok, Jido.AI.Reasoning.Result.t()} | {:error, Jido.AI.Error.t()}
```

`capabilities/0` declares whether the method supports tools, streaming, structured output, steering, and parallel candidates. Profile validation rejects unsupported combinations before a request starts.

The proposed first-release method set is:

- `:react`
- `:chain_of_thought`
- `:chain_of_draft`
- `:algorithm_of_thoughts`
- `:tree_of_thoughts`
- `:graph_of_thoughts`
- `:trm`
- `:adaptive`

This list is pending approval. A method can be retained as experimental without becoming a stable public contract.

A plan is portable output:

```elixir
%Jido.AI.Plan{
  goal: term(),
  steps: [Jido.AI.Plan.Step.t()],
  assumptions: [term()],
  metadata: map()
}
```

Producing, validating, revising, or scoring a plan is in this seam. Executing a plan as a generic workflow is not.

## Requirements

### Method definition

`RSN-REQ-001`: Each public reasoning method shall have a stable identifier, option schema, state schema, capability declaration, Flow factory, and result contract.

`RSN-REQ-002`: Method options and state shall be portable data and shall reject unknown fields at untrusted boundaries.

`RSN-REQ-003`: A method shall use seam 02 for every model call and seam 03 for every local tool call.

`RSN-REQ-004`: A method shall use public Flow components for branching, fan-out, reduction, iteration, subflows, and continuation.

`RSN-REQ-005`: A method shall not create a worker pool, private task supervisor, graph scheduler, or direct Runic workflow.

### Method behavior

`RSN-REQ-006`: ReAct shall alternate model decisions and approved tool batches until final answer, failure, cancellation, or a limit.

`RSN-REQ-007`: Linear methods shall preserve prompt-step order and shall return one final answer or structured result.

`RSN-REQ-008`: Search methods shall assign stable candidate identifiers before concurrent evaluation.

`RSN-REQ-009`: Search methods shall define deterministic score ordering and a deterministic tie-break rule.

`RSN-REQ-010`: When a method prunes candidates, it shall retain the reason and score data required for safe diagnostics.

`RSN-REQ-011`: An Adaptive method shall select only a declared method whose capabilities satisfy the request.

`RSN-REQ-012`: When a method does not support a requested feature, profile validation shall fail before model execution.

### Bounds and results

`RSN-REQ-013`: Each method shall declare finite defaults and hard maxima for its iterations, candidates, depth, breadth, and model calls as applicable.

`RSN-REQ-014`: The execution seam shall apply the most restrictive method, profile, request, and Exec bounds.

`RSN-REQ-015`: Every terminal method result shall include method ID, status, value, termination reason, usage, and safe method metadata.

`RSN-REQ-016`: A method result shall not expose private chain-of-thought by default.

`RSN-REQ-017`: When a method retains reasoning details, policy shall identify whether the data is private, provider-required, or safe for user output.

### Planning

`RSN-REQ-018`: Planning shall produce a validated portable plan value with stable step identifiers and declared dependencies.

`RSN-REQ-019`: Planning shall not execute a plan unless the plan is explicitly lowered to a `Jido.Flow` or submitted to a host-owned orchestrator.

`RSN-REQ-020`: When a plan is lowered to Flow, every executable plan step shall resolve to an approved Action or Subflow through a trusted registry.

`RSN-REQ-021`: An encoded plan shall not contain anonymous functions, PIDs, provider clients, or unregistered executable targets.

### Extensibility

`RSN-REQ-022`: A custom method shall register through a trusted method registry and shall pass the same option, state, capability, and Flow validation as built-in methods.

`RSN-REQ-023`: The Agent DSL and profile codec shall refer to methods by stable identifiers and portable options.

## Public contract

Recommended values:

```elixir
Jido.AI.Reasoning.Method
Jido.AI.Reasoning.State.t()
Jido.AI.Reasoning.Candidate.t()
Jido.AI.Reasoning.Score.t()
Jido.AI.Reasoning.Result.t()
Jido.AI.Plan.t()
Jido.AI.Plan.Step.t()
```

Recommended registry contract:

```elixir
Jido.AI.Reasoning.Registry.resolve(method_id) ::
  {:ok, module()} | {:error, Jido.AI.Error.t()}

Jido.AI.Reasoning.build(method_id, profile, opts \\ []) ::
  {:ok, Jido.Flow.t()} | {:error, Jido.AI.Error.t()}
```

Built-in methods can supply DSL helpers, but those helpers must expand to standard Jido AI profile data or standard `Jido.Flow` declarations. They cannot introduce a second runtime.

## Invariants

- `RSN-INV-001`: A reasoning method owns AI semantics, not execution mechanics.
- `RSN-INV-002`: Every method execution is finite under declared limits.
- `RSN-INV-003`: Candidate identity and score ordering are stable.
- `RSN-INV-004`: Private reasoning is not user-visible by default.
- `RSN-INV-005`: A plan is data until Flow or a host executes it.
- `RSN-INV-006`: A custom method uses the same public contracts as a built-in method.
- `RSN-INV-007`: Unsupported feature combinations fail before provider work.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 07 Sessions | Stable method state, terminal results, limits, and steering capability |
| 08 Capabilities | Composable method selection and policy declarations |
| 10 Authoring | Stable method identifiers, schemas, and feature validation |
| 11 Checkpoints | Portable method state and termination data |
| 12 Observation | Method, candidate, score, and termination metadata without private reasoning |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `RSN-DEC-001` | Which methods are stable in the first V3 release? | ReAct, Chain-of-Thought, Chain-of-Draft, and Adaptive; mark the other search methods experimental until aligned | Reduces the first stable compatibility surface |
| `RSN-DEC-002` | Can a plan execute directly? | No; lower to Flow or send to a host orchestrator | Keeps plan semantics separate from workflow execution |
| `RSN-DEC-003` | How are score ties resolved? | Stable candidate insertion order after normalized score | Makes concurrent search reproducible |
| `RSN-DEC-004` | Can methods retain hidden reasoning? | Only through explicit policy and never in public output by default | Protects sensitive reasoning data |
