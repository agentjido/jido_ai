> Target seam design. This document is pending approval.

# Model gateway and request preparation design

## Scope and owner

- Owner: `Jido.AI`, `Jido.AI.Models`, model Actions, model routing, and request-transform modules.
- In scope: Model references, aliases, selection, provider binding, request preparation, ReqLLM calls, streaming, response normalization, structured-output calls, and provider errors.
- Out of scope: Agent lifecycle, tool execution, Flow execution, request sessions, credentials, provider-client supervision, and generic retry scheduling.

## V2 capability anchor

V2 supplied direct text and object generation, stream generation, model aliases, provider options, model-routing policy, request transformers, LLM Actions, and normalized errors. V3 keeps this surface and places every provider operation behind one gateway that can be used from a Jido Action.

| V2 capability | V3 target |
| --- | --- |
| Direct `Jido.AI` generation calls | Thin facade over one model gateway |
| LLM Actions | Normal `Jido.Action` modules that call the gateway |
| Model option maps | Validated request options with explicit precedence |
| Model routing Plugin | Pure selection policy plus runtime resource binding |
| Request transformer callbacks | Ordered, named, validated transform stages |
| Provider response handling | Convert immediately to seam 01 values |

## Model

The gateway pipeline is:

```text
AI request
  -> resolve profile model alias
  -> apply model-routing policy
  -> resolve host-bound provider resource
  -> build provider-neutral request
  -> apply ordered request transforms
  -> convert through the ReqLLM adapter
  -> call or stream
  -> normalize Turn, Usage, and Error values
  -> validate or repair structured output when configured
```

A model reference is portable data. It can name a concrete model or a profile alias. Credentials, HTTP clients, connection pools, and ReqLLM runtime objects are runtime bindings.

Request option precedence is, from lowest to highest:

1. Package defaults.
2. Profile model defaults.
3. Model-routing decision defaults.
4. Trusted AgentServer caller context.
5. Explicit direct-facade options.

Signal data cannot set credentials, HTTP transport options, provider clients, or other trusted runtime fields. A host can put trusted options in the core command context before admission.

Transform stages are ordered and named:

- `:input` changes portable query and context data before model selection.
- `:model` changes portable model selection and generation options.
- `:operation` changes the provider-neutral request before adapter conversion.
- `:output` changes a normalized Turn or structured result after provider conversion.

Each transform returns a tagged tuple and cannot perform hidden Agent state mutation.

## Requirements

### Model resolution

`MDL-REQ-001`: When a request names a profile model alias, the gateway shall resolve the alias at request start against that profile's validated model table.

`MDL-REQ-002`: When model-routing policy selects a model, the gateway shall record the selected alias, concrete model identifier, and routing reason in request-local metadata.

`MDL-REQ-003`: When a model alias or concrete model cannot be resolved, the gateway shall return a validation error before a provider call starts.

`MDL-REQ-004`: A model reference stored in a profile, Signal, or checkpoint shall be portable data and shall not contain a provider client or credential.

### Request preparation

`MDL-REQ-005`: The gateway shall apply option precedence in the documented order and shall expose the effective safe options for diagnostics.

`MDL-REQ-006`: The gateway shall reject a provider or transport option that arrives through untrusted Signal data.

`MDL-REQ-007`: When request transforms are configured, the gateway shall run them in declared stage order and shall stop at the first error.

`MDL-REQ-008`: A request transform shall receive portable request data and explicit context and shall return `{:ok, value}` or `{:error, reason}`.

`MDL-REQ-009`: The gateway shall add structured-output instructions and provider schema data from the approved `Jido.AI.Output` contract.

### Provider calls and streaming

`MDL-REQ-010`: All text, object, embedding, and stream provider calls shall enter through the ReqLLM integration boundary.

`MDL-REQ-011`: A model Action shall call the gateway and shall return only public Jido Action result forms.

`MDL-REQ-012`: When a provider stream starts, the gateway shall assign one stable model-call identifier before it emits the first item.

`MDL-REQ-013`: The gateway shall preserve provider item order and shall assign a monotonic sequence number when the provider does not supply one.

`MDL-REQ-014`: When a stream ends normally, the gateway shall produce the same normalized terminal Turn and Usage value as the equivalent non-stream call.

`MDL-REQ-015`: When a stream fails or stops early, the gateway shall return a normalized error and shall not present partial content as a completed result.

### Response and output

`MDL-REQ-016`: Direct model calls shall keep the native ReqLLM response and usage contracts.

`MDL-REQ-017`: Agent runtime seams can convert ReqLLM values when an Agent contract needs a stable stored result.

`MDL-REQ-018`: When structured-output validation requests repair, the gateway shall perform only the bounded attempts allowed by the output contract.

`MDL-REQ-019`: Each repair call shall use a new model-call identifier and shall remain correlated with the parent AI request.

### Runtime resources and failure

`MDL-REQ-020`: When the gateway needs a provider client or credential, it shall resolve it from a trusted runtime binding supplied by the host.

`MDL-REQ-021`: Direct calls shall keep ReqLLM errors. Agent runtime seams shall preserve the provider cause in a bounded internal field when they convert an error.

`MDL-REQ-022`: The gateway shall classify retry eligibility but shall not schedule retry delay or create an independent retry worker.

## Public contract

Jido AI owns semantic aliases only. ReqLLM remains the native public model API:

```elixir
model = Jido.AI.Models.resolve(:capable)
ReqLLM.generate_text(model, query, opts)
ReqLLM.generate_object(model, query, output, opts)
ReqLLM.stream_text(model, query, opts)
```

Direct calls return native ReqLLM responses, streams, usage data, and errors.
The Jido AI runtime can add request policy and orchestration when a call is part
of an Agent Turn or Session.

Model Actions use the same gateway:

```elixir
Jido.AI.Actions.GenerateText
Jido.AI.Actions.GenerateObject
Jido.AI.Actions.Embed
```

The final module names are a compatibility decision. Their Action schemas shall use seam 01 values and their callbacks shall not access AgentServer internals.

Recommended policy callbacks:

```elixir
@callback select(models, request, context) ::
  {:ok, model_alias, metadata} | {:error, term()}

@callback transform(stage, value, context) ::
  {:ok, value} | {:error, term()}
```

## Invariants

- `MDL-INV-001`: One provider call has one stable model-call identifier.
- `MDL-INV-002`: Provider types do not cross the normalized result boundary.
- `MDL-INV-003`: Untrusted Signal data cannot set trusted provider options.
- `MDL-INV-004`: Stream order is preserved.
- `MDL-INV-005`: Structured-output repair is bounded by the output contract.
- `MDL-INV-006`: Model routing is a policy decision, not a process supervisor.
- `MDL-INV-007`: The gateway does not own Agent state or Flow execution.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 04 AI execution | Normalized calls, streams, turns, usage, errors, and retry eligibility |
| 05 Reasoning | Stable model selection and request-transform stages |
| 08 Capabilities | Pure routing and policy extension points |
| 10 Authoring | Portable model references and validated options |
| 12 Observation | Stable call identifiers and safe provider metadata |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `MDL-DEC-001` | When are aliases resolved? | At request start | Supports current routing without making profiles dynamic objects |
| `MDL-DEC-002` | Can direct calls accept trusted HTTP options? | Yes, through explicit facade options only | Keeps Signal input untrusted and supports advanced callers |
| `MDL-DEC-003` | What does a public stream emit? | Jido AI stream items with one terminal result | Removes ReqLLM stream coupling |
| `MDL-DEC-004` | Which generation Actions are public? | Text, object, and embedding Actions | Keeps a small stable Action surface |
