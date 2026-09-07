# Jido AI Agent Authoring Specification

Status: proposed target specification.

This document defines the Jido AI Agent authoring contract. It is an input to
source-code refinement. It does not describe only the current implementation.

The Elixir DSL is the preferred developer format. It is not the canonical
runtime format. Elixir DSL, Elixir data, JSON, YAML, and programmatic builders
must normalize to the same validated profile data.

In this document:

- **must** defines required behavior.
- **should** defines the preferred behavior.
- **can** defines optional behavior.

The design has one main rule:

> Keep the common case short. Add a block only when the Agent needs more than
> one value or more control. Normalize every authoring format to the same data.

## Canonical support Agent

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent, name: "support_agent"

  agent do
    schema Zoi.object(%{
      answer: Zoi.any() |> Zoi.default(nil)
    })

    ai :support do
      instructions "Help the operator resolve the support case."
      model :capable

      tools do
        action MyApp.Tools.SearchCases

        action :case_link, %{case_id: case_id},
          description: "Build a link to one support case.",
          schema: Zoi.object(%{case_id: Zoi.string()}),
          output_schema: Zoi.object(%{url: Zoi.string()}),
          context: context do
          url = MyApp.Support.case_url(context.tenant_id, case_id)

          {:ok, %{url: url}}
        end
      end

      result into: :answer
    end
  end

  routes do
    route "support.ask", ai: :support
  end
end
```

This is the canonical form for a one-model ReAct Agent. It shows one reusable
Action module and one inline Action.

- `use Jido.AI.Agent` creates a normal Jido Agent and installs the AI DSL.
- `ai :support` defines one named AI profile inside the Agent.
- `instructions` defines the system instructions.
- `model :capable` selects one configured model.
- ReAct is the default reasoning method, so there is no `reasoning` line.
- The `tools` block gives two Jido Actions to the model.
- `SearchCases` is a reusable Action module. It supplies its stable tool name.
- `:case_link` is an inline Action for small, local tool logic.
- `result into: :answer` stores the final result in Agent state.
- The route sends `support.ask` Signals to the `:support` AI profile.

## ELI5 view

The Agent is a worker with a mailbox and a notebook.

```text
support.ask Signal
        │
        ▼
AI profile :support
        │
        ├── job: help with a support case
        ├── brain: configured model :capable
        ├── method: ReAct, by default
        ├── tool: search_cases
        └── inline tool: case_link
        │
        ▼
Agent state field :answer
```

The route selects the AI profile. The profile defines how AI work is done. The
result declaration selects where the final value goes.

## Scope

This specification covers:

- AI profiles inside a normal Jido Agent.
- Fixed and dynamic instructions.
- One model, named model roles, exact LLMDB models, and model routing.
- Reasoning methods and their options.
- Local Actions, inline Actions, Flows, MCP tools, Ash resources, skills,
  browsers, catalogs, subagents, and handoffs.
- Request controls, operation approval, results, memory, and observability.
- Signal routes to AI profiles.
- Elixir DSL, Elixir data, JSON, YAML, and builder authoring.
- Compile-time and runtime validation.
- Inspection, export, import, and test requirements.

This specification does not require a new Agent runtime. AI profiles must
lower into normal Jido Agent configuration, routes, Actions, Flows, Plugins,
and state.

## Authoring formats

Jido AI must support these authoring formats.

| Format | Primary use | Can contain executable code? |
| --- | --- | --- |
| Elixir DSL | Preferred application source | Yes, through modules and inline Actions |
| Elixir map or keyword data | Tests, builders, and generated configuration | Module references only |
| Typed structs | Canonical internal and public data contract | Module references only |
| JSON | Portable stored definitions and APIs | No |
| YAML | Human-edited portable definitions | No |
| Programmatic builder | Dynamic application assembly | Module references only |

All formats must normalize through one public constructor. Conceptually:

```elixir
Jido.AI.Profile.new(input, registries: registries)
```

The constructor returns:

```elixir
{:ok, %Jido.AI.Profile{}}
```

or a structured validation error. The runtime must not have one behavior for
DSL profiles and another behavior for imported profiles.

### Authoring parity

The formats have semantic parity, not text parity.

- A string has the same meaning in Elixir, JSON, and YAML.
- An atom alias in Elixir uses a string alias in JSON and YAML.
- A module reference in Elixir uses a registry reference in JSON and YAML.
- An inline Action compiles to a normal Action module. Portable formats refer
  to that compiled Action through a registry. They cannot contain source code.
- Zoi schemas use direct values in Elixir and registry references in JSON and
  YAML.
- Import must not create atoms or resolve arbitrary modules from input text.

## Canonical data model

The complete Agent definition remains a normal Jido Agent definition. Each
`ai` declaration normalizes to one `%Jido.AI.Profile{}`.

The target profile shape is:

```elixir
%Jido.AI.Profile{
  id: :support,
  instructions: %Jido.AI.Source{},
  models: %{
    default: %Jido.AI.Model{}
  },
  model_router: nil,
  reasoning: %Jido.AI.Reasoning.Spec{},
  tools: %Jido.AI.ToolCatalog{},
  controls: %Jido.AI.Controls{},
  result: %Jido.AI.Result{},
  requests: %Jido.AI.RequestPolicy{},
  memory: %Jido.AI.MemoryPolicy{},
  observability: %Jido.AI.Observability{},
  metadata: %{}
}
```

The exact supporting module names can change during implementation. The field
boundaries and behavior in this specification must remain stable.

Canonical profile data must be:

- Validated.
- Inspectable.
- Free of provider clients, credentials, process identifiers, and closures.
- Safe to compare in golden tests.
- Encodable when all executable and schema references have registry names.

## Complete DSL shape

This is the complete target shape. Most Agents use only a small part of it.

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent, name: "support_agent"

  agent do
    schema MyApp.SupportAgentState

    ai :support do
      instructions MyApp.Prompts.SupportInstructions

      models do
        model :answer, :capable
        model :review, "anthropic:claude-sonnet-4-5"
        router MyApp.ModelRouter, fallback: :answer
      end

      reasoning :react,
        model: :answer,
        tool_concurrency: 4,
        options: %{max_steps: 8}

      tools do
        action MyApp.Tools.SearchCases

        action :case_link, %{case_id: case_id},
          description: "Build a link to one support case.",
          schema: Zoi.object(%{case_id: Zoi.string()}),
          output_schema: Zoi.object(%{url: Zoi.string()}),
          context: context do
          {:ok,
           %{
             url: MyApp.Support.case_url(context.tenant_id, case_id)
           }}
        end

        flow MyApp.Flows.ResolveCase, as: :resolve_case
        ash_resource MyApp.Support.Case, actions: [:read, :update]
        mcp_tools endpoint: :github, prefix: "github_"
        browser :docs, mode: :read_only, allow: ["https://hexdocs.pm"]
        catalog MyApp.SupportCatalog, prefix: "support_"
        skill MyApp.Skills.RefundPolicy
        load_path "priv/skills"
        subagent MyApp.ResearchAgent, as: :research_case
        handoff MyApp.BillingAgent, as: :billing_specialist
      end

      controls do
        max_iterations 8
        max_model_calls 12
        max_tool_calls 16
        timeout 60_000

        input MyApp.Controls.SafeInput
        model MyApp.Controls.ModelBudget

        operation MyApp.Controls.RequireApproval,
          when: [name: :resolve_case]

        output MyApp.Controls.SafeOutput
      end

      result schema: MyApp.SupportAnswer,
        into: :answer,
        max_repairs: 1,
        on_validation_error: :repair

      requests do
        mode :session
        on_busy :reject
        max_requests 100
        streaming true
        steering true
        idle_timeout 30_000
        tool_heartbeat 5_000
      end

      memory history: :messages

      observability do
        emit_telemetry true
        emit_signals true
        emit_llm_deltas false
        redact_tool_args true
      end

      metadata %{owner: "support", version: 1}
    end
  end

  routes do
    route "support.ask", ai: :support
  end
end
```

This example is a reference catalog. It is not the recommended starting size.

## Profile declaration

```elixir
ai :support do
  # profile declarations
end
```

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `id` | Atom in Elixir; string in portable data | None | Stable profile identifier |
| `instructions` | String, Action, or inline Action | Application default | System instructions source |
| `model` or `models` | Model input or model catalog | Application default | Model selection |
| `reasoning` | Reasoning specification | ReAct | Model and tool loop |
| `tools` | Tool-source declarations | Empty catalog | Model-callable work |
| `controls` | Staged controls and limits | Runtime defaults | Request policy |
| `result` | Result contract and state destination | No schema; destination required | Final output |
| `requests` | Turn or session request policy | Turn mode | Request lifecycle |
| `memory` | History state field and policy | No history | Conversation memory |
| `observability` | Emission and redaction overrides | Application defaults | Diagnostic output |
| `metadata` | Static map | `%{}` | Application-owned descriptive data |

The profile ID is required. A route and runtime request can use it. A module
can declare more than one profile. Profile IDs must be unique in one Agent.

## Instruction specification

Supported forms:

```elixir
instructions "Fixed system instructions."
instructions MyApp.Prompts.DynamicInstructions

instructions params, context: context do
  {:ok, %{instructions: MyApp.Prompts.for(context.tenant_id, params)}}
end
```

Canonical instruction sources are:

```text
default
fixed text
Action reference
compiled inline Action reference
```

An instruction Action runs once after input controls and before the first model
call. It receives the normalized request as Action parameters and trusted
request context as Action context.

Accepted successful Action values are:

```elixir
{:ok, %{instructions: text}}
{:ok, Jido.Action.Output.raw(text)}
```

`text` must be a non-empty string. An instruction Action error stops the
request before a provider call.

Portable data uses one of these forms:

```yaml
instructions: Fixed system instructions.
```

or:

```yaml
instructions:
  action: support_instructions
```

`support_instructions` must resolve through the supplied Action registry.

## Model specification

### Supported model inputs

```elixir
model :capable
model "anthropic:claude-sonnet-4-5"
model %{provider: :anthropic, id: "claude-sonnet-4-5"}
```

The first value is an application alias. The second and third values are exact
LLMDB-compatible model inputs.

### Named roles

```elixir
model :answer, :capable
model :review, "anthropic:claude-sonnet-4-5"
```

or:

```elixir
models do
  model :answer, :capable
  model :review, "anthropic:claude-sonnet-4-5"
end
```

The block is required only for multiple entries or a router. The singular and
block forms must normalize to the same model map.

### Model options

```elixir
model :answer, :capable,
  temperature: 0.2,
  max_tokens: 2_000,
  timeout: 30_000,
  provider_options: %{}
```

Supported common options are:

| Option | Type | Default |
| --- | --- | --- |
| `temperature` | Number | Provider or application default |
| `max_tokens` | Positive integer | Provider or application default |
| `timeout` | Positive integer in milliseconds | Request default |
| `provider_options` | Static map or keyword list | Empty |
| `metadata` | Static map | Empty |

Unknown provider-specific values belong inside `provider_options`. The DSL
must not add one macro for each provider parameter.

### Model router

```elixir
models do
  model :answer, :capable
  model :fast, :fast
  router MyApp.ModelRouter, fallback: :answer
end
```

A router is optional. It selects one declared model role for a request. It does
not create models and does not bypass the model catalog.

The router receives a bounded, inspectable request view. It returns:

```elixir
{:ok, :answer}
```

or an error. `fallback:` is used only when router policy permits fallback. An
unknown returned role is an error.

Portable data refers to a router through a router registry:

```yaml
models:
  entries:
    answer: capable
    fast: fast
  router:
    ref: support_model_router
    fallback: answer
```

## Reasoning specification

Supported methods are:

```text
react
chain_of_thought
chain_of_draft
algorithm_of_thoughts
tree_of_thoughts
graph_of_thoughts
trm
adaptive
```

The default is ReAct.

Supported forms:

```elixir
reasoning :react
reasoning :react, model: :answer
reasoning :react, model: "anthropic:claude-sonnet-4-5"

reasoning :react,
  model: :answer,
  tool_concurrency: 4,
  request_transformer: MyApp.RequestTransformer,
  options: %{max_steps: 8}
```

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `method` | Supported atom | `:react` | Reasoning implementation |
| `model` | Role, alias, or LLMDB input | Only or default model | Primary reasoning model |
| `tool_concurrency` | Positive integer | `4` | Maximum concurrent tool calls |
| `request_transformer` | Module reference | Method default | Provider request transformation |
| `options` | Static map | Method defaults | Method-specific settings |

Method-specific options must be validated by the selected reasoning method.
Methods that do not support tools, streaming, steering, or typed results must
reject those combinations during profile validation.

## Tool specification

All tool sources normalize to `%Jido.AI.Tool{}` entries in one catalog.

### Common tool options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `as` | Atom or string | Source name | Model-facing name override |
| `description` | String | Source description | Model-facing description override |
| `timeout` | Positive integer | `5_000` | Per-operation timeout |
| `max_retries` | Non-negative integer | `0` | Retry limit |
| `retry_backoff` | Non-negative integer | Runtime default | Retry delay |
| `forward_context` | Context policy | `:public` | Context sent to the tool |
| `idempotency` | `:idempotent` or `:unsafe_once` | `:idempotent` | Replay safety |
| `approval` | Boolean, atom, map, or keyword list | None | Human-review policy |
| `metadata` | Static map | `%{}` | Application data |

Valid context policies are:

```elixir
:public
:none
{:only, [:tenant_id]}
{:except, [:credential]}
```

Secrets and private runtime capabilities must never enter model arguments or
portable profile data.

### Action

```elixir
action MyApp.Tools.SearchCases
action MyApp.Tools.SearchCases, as: :find_cases, timeout: 10_000
```

The module must implement the Jido Action contract or a compatible public tool
conversion contract.

### Inline Action

```elixir
action :case_link, %{case_id: case_id},
  description: "Build a link to one support case.",
  schema: Zoi.object(%{case_id: Zoi.string()}),
  output_schema: Zoi.object(%{url: Zoi.string()}),
  context: context do
  {:ok, %{url: MyApp.Support.case_url(context.tenant_id, case_id)}}
end
```

Inline Actions must use `Jido.Action.Inline`. They must compile to ordinary
Action modules and use ordinary execution behavior.

### Flow

```elixir
flow MyApp.Flows.ResolveCase, as: :resolve_case
```

A Flow is exposed as one model-callable operation. The model selects the Flow.
The application owns the deterministic steps inside it.

### Ash resource

```elixir
ash_resource MyApp.Support.Case, actions: [:read, :update]
```

The source expands selected AshJido Actions into catalog entries. `actions:`
is an allowlist. An empty allowlist must not expose all mutation Actions by
accident.

### MCP tools

```elixir
mcp_tools endpoint: :github,
  prefix: "github_",
  tools: [:search_issues],
  discover: false,
  required: true,
  timeout: 10_000
```

| Option | Default | Purpose |
| --- | --- | --- |
| `endpoint` | Required | Configured MCP endpoint reference |
| `prefix` | Empty | Namespace for imported names |
| `tools` | Empty | Static allowlist or static metadata |
| `discover` | `false` | Permit discovery during planning |
| `required` | `false` | Fail planning when the source is unavailable |
| `timeout` | Request default | MCP request timeout |
| `transport` | None | Optional registered inline transport data |
| `client_info` | Application default | MCP client identification |
| `protocol_version` | Negotiated default | Requested protocol version |
| `capabilities` | `%{}` | MCP client capabilities |
| `timeouts` | `%{}` | Operation-specific timeout data |

Runtime discovery must be explicit. Compilation must not require network
access.

### Browser

```elixir
browser :docs,
  mode: :read_only,
  allow: ["https://hexdocs.pm"]
```

A browser source must state its mode and allowlist. Write-capable browser tools
must require explicit policy and cannot be enabled by the read-only default.

### Catalog

```elixir
catalog MyApp.SupportCatalog,
  prefix: "support_",
  timeout: 1_500,
  max_calls: 12,
  max_parallel_calls: 8,
  require_read_only: true
```

A catalog can expand many Actions behind one governed source. Host limits are
ceilings. Model input can select a smaller limit but cannot raise a ceiling.

### Skills

```elixir
skill MyApp.Skills.RefundPolicy
load_path "priv/skills"
```

A skill can add instructions, tools, and resource references. `load_path` can
load one `SKILL.md` file or a directory.

Advanced skill-source options are:

| Option | Default | Purpose |
| --- | --- | --- |
| `trust` | `false` for imported paths | Permit trusted local loading |
| `resource_policy` | Application default | Resource access policy |
| `resource_provider` | Application default | Resource loader reference |
| `max_depth` | Application default | Directory traversal depth |
| `max_directories` | Application default | Directory count limit |
| `exclude_directories` | `[]` | Excluded directory names |

These values can use a future `skills do` block if the flat tool list becomes
hard to read. The canonical data must not depend on the chosen layout.

### Subagent

```elixir
subagent MyApp.ResearchAgent,
  as: :research_case,
  timeout: 30_000,
  forward_context: {:only, [:tenant_id]},
  result: :structured
```

A subagent performs one bounded task. The parent receives its result and keeps
ownership of the conversation.

### Handoff

```elixir
handoff MyApp.BillingAgent,
  as: :billing_specialist,
  target: :auto,
  forward_context: :public
```

A handoff records who owns future turns. It does not transfer execution in the
middle of the current turn.

## Control specification

```elixir
controls do
  max_iterations 8
  max_model_calls 12
  max_tool_calls 16
  timeout 60_000
  input MyApp.Controls.SafeInput
  model MyApp.Controls.ModelBudget
  operation MyApp.Controls.RequireApproval, when: [name: :refund_order]
  output MyApp.Controls.SafeOutput
end
```

| Declaration | Default | Boundary |
| --- | --- | --- |
| `max_iterations` | Method default | Complete reasoning loop |
| `max_model_calls` | Method default plus repairs | Provider calls |
| `max_tool_calls` | Method default | Tool calls |
| `timeout` | `60_000` | Complete request wall time |
| `input` | None | Before instruction resolution and model calls |
| `model` | None | Before and after each provider call |
| `operation` | None | Before and after each tool call |
| `output` | None | After validation and before commit |

Controls run in declaration order. A control can continue, block, interrupt,
or return an error. Interrupt must create a resumable request state.

An operation control can use `when:` with `kind`, `name`, or other stable tool
metadata. Match data must be static and portable.

Tool-local `approval:` is concise policy syntax. It must lower to the same
operation-control and resume path.

The target public DSL does not expose raw `effect_policy` or one global
`tool_interceptor`. Staged controls replace those unclear options. Internal
effect policy and interceptors can remain implementation mechanisms.

## Result specification

Supported forms:

```elixir
result into: :answer

result schema: MyApp.SupportAnswer,
  into: :answer,
  max_repairs: 1,
  on_validation_error: :repair,
  repair_action: MyApp.RepairSupportAnswer
```

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `schema` | Zoi schema or registry reference | None | Structured-value contract |
| `into` | Agent state field | Required | Commit destination |
| `max_repairs` | Integer from `0` to `3` | `0` | Validation repair limit |
| `on_validation_error` | `:repair` or `:error` | `:repair` when repairs are enabled | Failure behavior |
| `repair_action` | Action reference | Built-in repair request | Custom repair request |

The completed request keeps:

```text
content  final assistant text
value    validated structured value, or nil
usage    normalized model usage
events   request events
trace    safe diagnostic data
```

For an unstructured result, `into` receives `content`. For a structured
result, `into` receives `value`. The request record keeps both.

Validation and all repairs occur before the Agent state commit. A failed result
must not partially update the destination field.

## Request specification

```elixir
requests do
  mode :turn
  on_busy :reject
  max_requests 100
  streaming false
  steering false
  idle_timeout 30_000
  tool_heartbeat 5_000
end
```

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `mode` | `:turn` or `:session` | `:turn` | Request execution mode |
| `on_busy` | `:reject` | `:reject` | Concurrent request behavior |
| `max_requests` | Positive integer | `100` | Retained request limit |
| `streaming` | Boolean | `false` | Stream model and lifecycle events |
| `steering` | Boolean | `false` | Accept input during execution |
| `idle_timeout` | Non-negative milliseconds | None | Session inactivity timeout |
| `tool_heartbeat` | Non-negative milliseconds | None | Long tool activity event interval |

Steering requires session mode and a reasoning method that supports steering.
Idle timeout and tool heartbeat apply only where the runtime can emit session
activity.

## Memory specification

```elixir
memory history: :messages
```

The history value names an Agent state field. That field must exist and must
be different from the result destination.

Future memory options can include scope, entry limits, recall, and persistence.
They must normalize to one memory policy. External memory work must occur
through Actions or capabilities, not hidden functions in profile data.

## Observability specification

```elixir
observability do
  emit_telemetry true
  emit_signals true
  emit_llm_deltas false
  redact_tool_args true
end
```

| Option | Default | Purpose |
| --- | --- | --- |
| `emit_telemetry` | Application default | Emit standard telemetry events |
| `emit_signals` | Application default | Emit Jido lifecycle Signals |
| `emit_llm_deltas` | `false` | Include provider text deltas |
| `redact_tool_args` | `true` | Remove tool arguments from safe diagnostics |

Normal telemetry must work without this block. This block only overrides
application policy. Redaction must occur before data enters events, logs,
snapshots, or request inspection output.

## Signal route specification

```elixir
routes do
  route "support.ask", ai: :support
end
```

The compiler must resolve `ai: :support` to the generated profile entry Flow or
Action. It must use the normal Jido route model. An unknown profile is a compile
error.

AI routes can use the normal route options that Jido supports. The AI extension
must not create a second route table.

## Default resolution

Defaults resolve in this order:

```text
request override
profile declaration
Agent declaration
application configuration
Jido AI package default
```

A lower layer cannot silently replace an explicit value from a higher layer.
Inspection and preflight must show the resolved value and its source.

Default behavior is:

- Configured default instructions.
- Configured default model.
- ReAct reasoning.
- No tools.
- Runtime control limits.
- Turn request mode.
- No history memory.
- Standard telemetry with safe redaction.

## Portable JSON and YAML shape

The portable shape mirrors canonical profile data:

```yaml
version: 1
agent:
  name: support_agent
  schema:
    ref: support_agent_state
  profiles:
    support:
      instructions:
        action: support_instructions
      models:
        entries:
          answer: capable
          review: anthropic:claude-sonnet-4-5
        router:
          ref: support_model_router
          fallback: answer
      reasoning:
        method: react
        model: answer
      tools:
        - kind: action
          ref: search_cases
        - kind: mcp_tools
          endpoint: github
          prefix: github_
      result:
        schema:
          ref: support_answer
        into: answer
        max_repairs: 1
      requests:
        mode: turn
  routes:
    - type: support.ask
      target:
        ai: support
```

Import receives explicit registries:

```elixir
registries = %{
  actions: %{
    "search_cases" => MyApp.Tools.SearchCases,
    "support_instructions" => MyApp.Prompts.SupportInstructions
  },
  model_routers: %{
    "support_model_router" => MyApp.ModelRouter
  },
  schemas: %{
    "support_agent_state" => MyApp.SupportAgentState,
    "support_answer" => MyApp.SupportAnswer
  }
}
```

Unknown references are import errors. Import must not use `String.to_atom/1`,
`Module.concat/1`, or dynamic code evaluation on untrusted input.

## Builder API

The builder API is a thin constructor for canonical data:

```elixir
{:ok, profile} =
  Jido.AI.profile(
    id: :support,
    instructions: "Help the operator.",
    model: :capable,
    reasoning: :react,
    tools: [MyApp.Tools.SearchCases],
    result: [into: :answer]
  )
```

It must use the same defaults and validators as the DSL and import paths. It
must not be a separate feature set.

## Validation phases

### Compile-time validation

The Elixir DSL must check all static facts:

- Unique profile IDs.
- Valid instruction source shape.
- Valid model inputs and unique model roles.
- Valid reasoning method and known model role.
- Static option values.
- Available Action, Flow, control, router, and schema modules.
- Unique final tool names across all sources known at compilation.
- Valid inline Action headers and schemas.
- Existing result and history fields in the Agent schema.
- Compatible reasoning, tool, result, streaming, and steering features.
- Known AI profile route targets.

### Import validation

Import must check the same semantic rules after registry resolution. Errors
must include the document path and safe source location when available.

### Planning validation

Planning checks facts that can change after compilation:

- Application aliases and LLMDB model resolution.
- Required MCP endpoints and optional discovery.
- Dynamic tool-name conflicts.
- Runtime capability availability.
- Request and context policy.
- Final resolved limits.

Planning must not call a model or execute a tool.

### Runtime validation

Runtime checks:

- Request input and trusted context.
- Instruction Action output.
- Provider responses.
- Tool arguments and results.
- Controls and approval.
- Structured result values and repair bounds.
- State commit validity.

## Lowering and execution

The implementation pipeline is:

```text
DSL / map / struct / JSON / YAML / builder
                    │
                    ▼
          validated Profile data
                    │
                    ▼
          resolved execution plan
                    │
                    ▼
 Jido route → input controls → instructions → reasoning loop
                    │                         │
                    │                         ├── model controls and calls
                    │                         └── operation controls and tools
                    ▼
       result validation and repair
                    │
                    ▼
          output controls → state commit
```

Profile construction is inert. It does not call models, tools, MCP endpoints,
or external stores.

## Inspection and export

The public API must support:

```elixir
MyApp.SupportAgent.ai_profiles()
MyApp.SupportAgent.ai_profile(:support)
Jido.AI.inspect(MyApp.SupportAgent, profile: :support)
Jido.AI.preflight(MyApp.SupportAgent, request, profile: :support)
Jido.AI.export(MyApp.SupportAgent, :yaml)
Jido.AI.import(yaml, registries: registries)
```

`inspect` returns a safe view of canonical data. `preflight` resolves the
prompt, models, tools, controls, and result contract without an external call.
Export fails with a structured error when an executable or schema reference
has no portable registry name.

## Generated module API

`use Jido.AI.Agent` should add only stable convenience functions. It must keep
the normal `Jido.Agent` API.

Expected AI functions are:

```elixir
ai_profiles()
ai_profile(id)
ask(server, query, options \\ [])
ask_sync(server, query, options \\ [])
ask_stream(server, query, options \\ [])
await(request, options \\ [])
cancel(server, options \\ [])
steer(server, content, options \\ [])
```

Functions that need one profile accept `profile: :support`. An Agent with one
profile can use that profile by default. An Agent with multiple profiles must
receive a profile or use a route that selects one.

## Composition with `Jido.Agent`

`Jido.AI.Agent` must be a small convenience entry point. It must not create a
second Agent type or runtime.

Conceptually, this:

```elixir
use Jido.AI.Agent, name: "support_agent"
```

means this:

```elixir
use Jido.Agent,
  name: "support_agent",
  extensions: [Jido.AI.DSL]
```

An application can use either entry point:

```elixir
use Jido.AI.Agent, name: "support_agent"
```

or:

```elixir
use Jido.Agent,
  name: "support_agent",
  extensions: [Jido.AI.DSL, MyApp.OtherExtension]
```

Both forms must produce the same Agent structure and runtime behavior. The
second form is useful when an application wants to list all extensions.

## Jidoka design lessons

The local Jidoka source and the published package have several design choices
that should move into Jido AI.

### Keep the authoring surface small

Jidoka starts with this valid Agent:

```elixir
defmodule MyApp.Assistant do
  use Jidoka.Agent

  agent :assistant
end
```

It gets its model and instructions from configuration. Jido AI should keep the
same property. A profile can override defaults, but it does not have to repeat
them.

### Compile syntax to immutable data

Jidoka compiles its DSL to `Jidoka.Agent.Spec`. Jido AI should compile each
`ai` block to a validated `Jido.AI.Profile` value. The profile must contain
data and executable module references. It must not contain runtime closures,
provider clients, credentials, or processes.

This gives Elixir authoring, JSON or YAML import, inspection, and tests one
common contract.

### Normalize all tool sources

Jidoka lets `action`, `ash_resource`, `mcp_tools`, `workflow`, `skill`,
`subagent`, and `handoff` use different authoring syntax. It then compiles them
to one operation contract.

Jido AI should use the same pattern:

```text
clear source-specific DSL
          │
          ▼
one validated tool or operation catalog
          │
          ▼
one reasoning runtime boundary
```

The DSL should not make an MCP server or Ash resource pretend to be one Action.
The compiler adapter should do that normalization.

### Separate text from structured data

Jidoka keeps assistant text in `Turn.Result.content` and validated output in
`Turn.Result.value`. Jido AI should preserve the same distinction in its full
request result. This removes the need for an `AI Summarizer` only to obtain
plain text from a rich result.

### Keep inspection out of the DSL

Jidoka provides `inspect` and `preflight` APIs. They do not add flags to each
Agent. Jido AI should also make the compiled profile, assembled prompt, model,
tool definitions, and result contract inspectable without a provider call.

Observability should have useful runtime defaults. Authors should add DSL only
for policy changes, such as redaction. They should not have to enable normal
telemetry on each Agent.

### Test the compiled contract

Jidoka has golden tests that compare DSL source with the normalized spec. Jido
AI needs the same test layers:

1. DSL-to-profile golden tests.
2. Compile-error tests for invalid combinations and references.
3. Runtime tests with fake model and tool capabilities.
4. Import parity tests when JSON or YAML authoring is added.
5. Formatter tests for all public macros.

### Keep runtime durability below the authoring API

Jidoka's effect intents, results, journal, snapshots, and resume path are useful
runtime contracts. They should inform Jido AI request execution. They should
not make the small Agent declaration longer.

## Exact formatter export

The target formatter export must cover these local calls and all arities that
the implementation exposes:

```elixir
ai_locals = [
  ai: 2,
  instructions: 1,
  instructions: 2,
  model: 1,
  model: 2,
  model: 3,
  models: 1,
  router: 1,
  router: 2,
  reasoning: 1,
  reasoning: 2,
  tools: 1,
  action: 1,
  action: 2,
  action: 3,
  flow: 1,
  flow: 2,
  ash_resource: 1,
  ash_resource: 2,
  mcp_tools: 1,
  browser: 1,
  browser: 2,
  catalog: 1,
  catalog: 2,
  skill: 1,
  load_path: 1,
  subagent: 1,
  subagent: 2,
  handoff: 1,
  handoff: 2,
  controls: 1,
  max_iterations: 1,
  max_model_calls: 1,
  max_tool_calls: 1,
  timeout: 1,
  input: 1,
  input: 2,
  operation: 1,
  operation: 2,
  output: 1,
  output: 2,
  result: 1,
  requests: 1,
  mode: 1,
  on_busy: 1,
  max_requests: 1,
  streaming: 1,
  steering: 1,
  idle_timeout: 1,
  tool_heartbeat: 1,
  memory: 1,
  observability: 1,
  emit_telemetry: 1,
  emit_signals: 1,
  emit_llm_deltas: 1,
  redact_tool_args: 1,
  metadata: 1
]

[
  import_deps: [:jido, :jido_action],
  locals_without_parens: ai_locals,
  export: [locals_without_parens: ai_locals]
]
```

The implementation can remove an arity that is not part of its final macro
shape. It must not omit an arity that appears in supported source.

## Current-to-target source map

The current source already has useful profile, reasoning, request, result,
control, tool, skill, and lowering code. Refinement should change the public
shape without creating a parallel runtime.

| Current concept | Target behavior |
| --- | --- |
| `ai_profile` internal entity | Public `ai :id do` declaration |
| Required `models do` block | Optional `model` shorthand or `models` block |
| Required `reasoning` entity | Optional; defaults to ReAct and the only model |
| Required `result nil, into:` shape | `result into:` without a public `nil` schema |
| String-only instructions | String, named Action, or inline Action |
| Required Action `as:` | Use the Action name; `as:` is an override |
| Action and Flow tools only | Normalize all specified tool sources to one catalog |
| Model `generation:` keyword list | Direct model options with provider values nested under `provider_options` |
| `repair_fun` | Portable `repair_action` module or registry reference |
| Profile `tool_context` | Trusted request context plus per-tool `forward_context` |
| Profile `tool_interceptor` | Staged operation controls |
| Raw profile `effect_policy` | Staged controls and tool-local approval |
| Observability question-mark fields | Formatter-friendly observability declarations |
| Elixir DSL only | Shared constructors for DSL, data, builders, JSON, and YAML |
| Internal profile lookup | Public safe inspection and preflight APIs |

Compatibility adapters can accept old values during migration. New canonical
data and exported documents must use only the target names.

## Source refinement map

The first implementation pass should use these current source areas:

| Source area | Required refinement |
| --- | --- |
| `lib/jido_ai/authoring/dsl.ex` | Add the target entities, shorthand forms, inline Action hosts, and formatter-facing macro arities |
| `lib/jido_ai/authoring/profile.ex` | Make one constructor own normalization, defaults, compatibility checks, and structured errors |
| `lib/jido_ai/authoring/authoring.ex` | Lower normalized profiles into normal Jido configuration and AI route targets |
| `lib/jido_ai/authoring/agent.ex` | Install the extension and expose the small generated module API |
| `lib/jido_ai/authoring/capability.ex` | Validate Agent state destinations and extension capabilities |
| `lib/jido_ai/operations/runtime.ex` | Resolve instructions, models, reasoning, controls, tools, and result contracts for one request |
| `lib/jido_ai/operations/run.ex` | Keep final state commit atomic and write the selected result value |
| `lib/jido_ai/operations/tool_interception.ex` | Become the internal execution layer for staged operation controls |
| `lib/jido_ai/skill/source.ex` and skill runtime modules | Normalize skill modules, paths, resources, and contributed tools |
| `lib/jido_ai/session/` | Enforce request mode, retention, streaming, steering, idle timeout, and resume behavior |
| New codec and registry modules | Add safe versioned JSON and YAML import and export |
| `.formatter.exs` | Export the complete DSL `locals_without_parens` list |

The implementation should extend these modules before it creates replacement
subsystems. Old compatibility entry points can lower into the new constructors.

The test structure should include:

```text
test/jido_ai/authoring/dsl/
├── defaults_test.exs
├── instructions_test.exs
├── models_test.exs
├── reasoning_test.exs
├── tools_test.exs
├── controls_test.exs
├── result_test.exs
├── requests_test.exs
├── memory_test.exs
├── observability_test.exs
├── routes_test.exs
├── formatter_test.exs
└── golden_profile_test.exs

test/jido_ai/authoring/portable/
├── map_test.exs
├── json_test.exs
├── yaml_test.exs
├── registry_test.exs
└── parity_test.exs
```

## Implementation order

### Phase 1: canonical constructors

- Make `Jido.AI.Profile.new/2` the single normalization boundary.
- Add typed source, model, reasoning, tool, control, result, request, memory,
  and observability values.
- Keep constructors inert.
- Add safe projection for golden tests.

### Phase 2: preferred Elixir DSL

- Install the extension through `use Jido.AI.Agent` and `use Jido.Agent`.
- Add singular model and default reasoning expansion.
- Add instruction Action sources.
- Add the `ai: :profile` route target.
- Export the formatter entries.

### Phase 3: tool-source parity

- Add portable inline Actions.
- Make `as:` optional for module Actions.
- Add Ash, MCP, browser, catalog, skill, subagent, and handoff compilers.
- Detect names after all static and discovered sources normalize.

### Phase 4: controls and results

- Lower staged controls to the existing runtime boundaries.
- Lower approval to the same interrupt and resume path.
- Preserve separate `content` and `value` results.
- Make state commit atomic after output validation.

### Phase 5: portable authoring

- Add map, keyword, and builder inputs.
- Add versioned JSON and YAML codecs.
- Add explicit registries and safe reference resolution.
- Add import and export parity tests.

### Phase 6: Jidoka parity and archive readiness

- Verify tool-source parity.
- Verify control and approval parity.
- Verify structured result, inspection, preflight, session, snapshot, and resume
  parity.
- Publish migration documentation.
- Archive Jidoka only after applications can move without losing a required
  contract.

## Acceptance test matrix

### Authoring parity

For each portable fixture, Elixir DSL, Elixir data, builder, JSON, and YAML
must produce equal canonical projections.

Fixtures must cover:

- Defaults-only profile.
- Fixed instructions.
- Instruction Action.
- One alias model.
- One exact LLMDB model.
- Named model roles and router.
- Default and explicit reasoning.
- Each tool source.
- Controls and approval.
- Text and structured results.
- Turn and session request policies.
- Memory and observability.
- Multiple profiles and AI routes.

Inline Action fixtures compare the compiled Action reference with an imported
registry reference to the same Action. JSON and YAML do not contain the body.

### Compile errors

Tests must cover each compile-time rule in this document. Each error must name
the profile, declaration path, source line, invalid value class, and a short
fix when possible.

### Runtime behavior

Tests must use fake model and tool capabilities. They must cover:

- Direct final text.
- Repeated model and tool calls.
- Parallel tool bounds.
- Dynamic instructions.
- Model routing and fallback.
- Tool argument and output validation.
- Control continue, block, interrupt, error, and resume.
- Result validation, repair, and atomic commit.
- Streaming, steering, timeout, cancellation, and heartbeat.
- History read and write.
- Safe observability and redaction.

### Inspection and codecs

Tests must prove that:

- Preflight makes no provider or tool call.
- Inspection does not expose secrets.
- Export and import round-trip portable profiles.
- Unknown registry references fail safely.
- Import does not create atoms or evaluate code.
- Schema and codec versions reject unsupported future versions.

### Formatter

Formatter tests must run representative modules through `mix format` twice.
The second run must make no change. DSL declarations must remain without
optional parentheses.

## Final design decisions

1. A profile name is required. It is part of routing and inspection.
2. Exact LLMDB strings receive syntax validation during construction. Catalog
   and availability checks occur during planning or preflight.
3. Instruction Actions receive the normalized request as parameters and
   trusted request context as Action context.
4. An unstructured result destination receives `content`. A structured result
   destination receives `value`. The full request record keeps both.
5. All authoring formats have semantic parity. JSON and YAML use registries for
   executable and schema references.
6. ReAct is the default reasoning method.
7. Model, instructions, tools, and advanced controls can be omitted when safe
   defaults exist.
8. Raw effect policy, global tool context, and a global tool interceptor are
   not preferred public DSL options. Clear staged controls replace them.
9. The DSL is a compiler front end. Canonical profile data is the contract.
