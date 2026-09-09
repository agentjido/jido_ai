> Target seam design. This document is pending approval.

# AI values and result contracts design

## Scope and owner

- Owner: `Jido.AI.Query`, `Jido.AI.Context`, `Jido.AI.Turn`, `Jido.AI.Output`, `Jido.AI.Usage`, and `Jido.AI.Error`.
- In scope: Portable query content, conversation entries, model turns, output contracts, usage, result metadata, errors, validation, redaction, and codec rules.
- Out of scope: Provider calls, tool execution, request lifecycle, Agent commit, storage, process ownership, and transport.

## V2 capability anchor

V2 supplied text and multimodal queries, conversation context, normalized model turns, structured output, usage metadata, and typed errors. V3 retains these capabilities and makes their public representation provider-neutral and portable.

| V2 capability | V3 target |
| --- | --- |
| String or provider content-part query | `Jido.AI.Query` with Jido AI content parts and explicit provider conversion |
| Conversation context | Portable `Jido.AI.Context` entries in chronological semantic order |
| Model response maps | Validated `Jido.AI.Turn` with ordered content and tool calls |
| Structured output options | Validated `Jido.AI.Output` contract with Zoi or JSON Schema input |
| Provider usage maps | Canonical token and cost fields plus bounded provider metadata |
| Nested AI exceptions | Stable Jido AI error category, code, message, details, and cause |

## Model

The value layer has six primary values:

1. `Jido.AI.Query` is validated text or a nonempty ordered list of Jido AI content parts.
2. `Jido.AI.Context` is an identified ordered conversation with `user`, `assistant`, `tool`, and `system` entries.
3. `Jido.AI.Turn` is one normalized model response. It is either a final answer or an ordered tool-call request.
4. `Jido.AI.Output` is a structured-output contract. It contains a schema, validation mode, and bounded repair policy.
5. `Jido.AI.Usage` is canonical usage data with optional bounded provider extensions.
6. `Jido.AI.Error` is the common AI failure value.

Provider adapters convert between these values and ReqLLM values. ReqLLM structs are accepted only at explicitly documented adapter functions. They do not appear in stable encoded data.

Content parts use a closed tagged form:

```elixir
%{type: :text, text: String.t()}
%{type: :image, source: portable_source(), media_type: String.t() | nil}
%{type: :file, file_id: String.t(), media_type: String.t() | nil, metadata: map()}
%{type: :thinking, text: String.t(), visibility: :private | :public}
```

The final list and fields require approval. Unknown types are validation errors.

## Requirements

### Construction and validation

`VAL-REQ-001`: When a caller constructs a public AI value, the owning module shall validate it with a Zoi schema and return `{:ok, value}` or `{:error, %Jido.AI.Error{}}`.

`VAL-REQ-002`: Each public AI value shall reject unknown fields by default at an encoded or untrusted boundary.

`VAL-REQ-003`: Each portable AI value shall contain only data accepted by the package portability rule.

`VAL-REQ-004`: When a string-keyed map enters a public schema, the owning module shall normalize only known keys and shall not create atoms from untrusted input.

### Query and content

`VAL-REQ-005`: A query shall be nonempty text or a nonempty ordered list of supported content parts.

`VAL-REQ-006`: When a caller adds a file reference, the query contract shall preserve the file identifier, media type, filename, and safe metadata without requiring a provider struct.

`VAL-REQ-007`: When Jido AI summarizes multimodal content for logs or events, it shall not expose binary content, file bytes, credentials, or hidden thinking text.

### Context and turn

`VAL-REQ-008`: A context shall preserve semantic message order, roles, tool-call correlation, reasoning details when allowed, and caller references.

`VAL-REQ-009`: Projection to a provider request shall be an adapter operation and shall not change the stored context.

`VAL-REQ-010`: A normalized turn shall identify exactly one response class: `:final_answer` or `:tool_calls`.

`VAL-REQ-011`: A turn with tool calls shall preserve provider order and stable call identifiers.

`VAL-REQ-012`: A turn shall preserve ordered visible content separately from private thinking or provider reasoning details.

### Structured output

`VAL-REQ-013`: An output contract shall accept an object-shaped Zoi schema or object-shaped JSON Schema and shall reject a non-object root.

`VAL-REQ-014`: When output validation fails, the output contract shall apply the configured `:error` or bounded `:repair` policy.

`VAL-REQ-015`: A repair attempt shall never exceed the configured retry limit and shall return the last validation error when the limit is reached.

`VAL-REQ-016`: An output contract shall have a deterministic fingerprint based on its portable semantic fields.

### Usage and errors

`VAL-REQ-017`: Usage normalization shall provide nonnegative `input_tokens`, `output_tokens`, and `total_tokens` when provider data contains those counts.

`VAL-REQ-018`: Usage merge shall sum known numeric counters and preserve bounded provider metadata without replacing canonical counters.

`VAL-REQ-019`: Every public AI error shall include a stable category and code, a safe message, bounded details, and an optional cause.

`VAL-REQ-020`: Error inspection and telemetry conversion shall redact credentials, request bodies, raw file content, and configured sensitive keys.

### Encoding and compatibility

`VAL-REQ-021`: Every value that can enter a Signal, profile, Agent state, or checkpoint shall have a versioned portable encoding contract.

`VAL-REQ-022`: A decoder shall reject an unsupported future version and shall identify the supported version range.

## Public contract

Recommended constructors and adapters:

```elixir
Jido.AI.Query.new(input) :: {:ok, Query.t()} | {:error, Jido.AI.Error.t()}
Jido.AI.Query.to_provider(query, adapter_opts) :: {:ok, term()} | {:error, Jido.AI.Error.t()}

Jido.AI.Context.new(opts) :: {:ok, Context.t()} | {:error, Jido.AI.Error.t()}
Jido.AI.Context.append(context, entry) :: {:ok, Context.t()} | {:error, Jido.AI.Error.t()}
Jido.AI.Context.project(context, adapter, opts) :: {:ok, [term()]} | {:error, Jido.AI.Error.t()}

Jido.AI.Turn.from_provider(response, adapter_opts) :: {:ok, Turn.t()} | {:error, Jido.AI.Error.t()}
Jido.AI.Output.new(attrs) :: {:ok, Output.t() | nil} | {:error, Jido.AI.Error.t()}
Jido.AI.Output.validate(output, value) :: {:ok, map()} | {:error, Jido.AI.Error.t()}
Jido.AI.Usage.normalize(provider_usage) :: Jido.AI.Usage.t()
Jido.AI.Error.normalize(term, context) :: Jido.AI.Error.t()
```

Bang constructors are allowed for trusted module and compile-time authoring. Runtime and encoded input use tagged tuples.

Compatibility applies to encoded semantic fields, not to debug fields, internal struct layout, or provider metadata. An adapter can accept a ReqLLM struct, but the stable returned value is owned by Jido AI.

## Invariants

- `VAL-INV-001`: Public portable values contain no provider client, process, function, task, monitor, or secret.
- `VAL-INV-002`: Conversation order and tool-call correlation are never changed by normalization.
- `VAL-INV-003`: A turn has one response class.
- `VAL-INV-004`: Structured output repair is bounded.
- `VAL-INV-005`: Provider types do not cross the stable value boundary.
- `VAL-INV-006`: Error and observation views are safe by default.
- `VAL-INV-007`: Decoding untrusted input never creates atoms.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 02 Model gateway | Provider-neutral queries, context, turns, output, usage, and errors |
| 03 Tool bridge | Stable content, tool-call correlation, and error values |
| 04 AI execution | Deterministic context and terminal result data |
| 07 Request sessions | Portable request record payloads and errors |
| 10 Authoring | Validated output and content contracts for profiles |
| 11 Checkpoints | Versioned portable values |
| 12 Observation | Safe summary and redaction functions |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `VAL-DEC-001` | Are ReqLLM content parts public Jido AI query values? | No; convert at the adapter | Keeps portable values provider-neutral |
| `VAL-DEC-002` | Where does output repair execute? | Seam 02 executes the model call; seam 01 owns validation and repair policy | Separates value semantics from provider I/O |
| `VAL-DEC-003` | Are timestamps required in context entries? | Optional and preserved, but not part of semantic equality | Keeps deterministic tests and useful audit data |
| `VAL-DEC-004` | Is hidden thinking stored by default? | No; retain only when policy explicitly allows it | Reduces sensitive data retention |
