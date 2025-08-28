### Slide 1: Jido.Action in 15 minutes

Content:
- What actions are and why they exist
- Learning goals: define, compose, execute, handle errors, observe
- Real APIs and tests from jido_action

Code:
```elixir
# source: projects/jido_action/lib/jido_action.ex
defmodule MyAction do
  use Jido.Action, name: "my_action"
  @impl true
  def run(params, _ctx), do: {:ok, params}
end
```

Notes:
- Actions are validated, composable, AI-tool-friendly units
- We’ll use Jido.Exec, Instruction, Chain, and Tool
- All examples are in projects/jido_action

### Slide 2: Define your first action

Content:
- Use `Jido.Action` with name/description/schema
- Implement `run/2` returning `{:ok, map}` or `{:error, reason}`

Code:
```elixir
# source: projects/jido_action/README.md
defmodule MyApp.Actions.GreetUser do
  use Jido.Action,
    name: "greet_user",
    description: "Greets a user",
    schema: [
      name: [type: :string, required: true],
      language: [type: {:in, ["en", "es", "fr"]}, default: "en"]
    ]
  def run(params, _ctx) do
    {:ok, %{message: "Hello, #{params.name}!"}}
  end
end
```

Notes:
- Schema drives validation and tool generation
- Keep outputs maps; add fields as needed

### Slide 3: Parameter schemas with NimbleOptions

Content:
- Types, required, defaults, enums
- Docs on fields become tool param descriptions

Code:
```elixir
# source: projects/jido_action/guides/actions-guide.md
schema: [
  name: [type: :string, required: true],
  age: [type: :integer, min: 0, max: 150],
  active: [type: :boolean, default: true],
  tags: [type: {:list, :string}, default: []],
  email: [type: :string, required: true, doc: "User's email"],
  status: [type: :atom, in: [:pending, :active, :inactive], default: :pending]
]
```

Notes:
- Only declared keys validated; extra keys pass through
- Use `doc:` for better AI tool UX

### Slide 4: Lifecycle hooks (middleware)

Content:
- Transform params pre/post validation
- Post-process results; compensate on errors

Code:
```elixir
# source: projects/jido_action/guides/actions-guide.md
def on_before_validate_params(params) do
  {:ok, Map.update(params, :data, "", &String.trim/1)}
end
@impl true
def on_after_run(result) do
  {:ok, Map.put(result, :logged, true)}
end
@impl true
def on_error(failed_params, error, _ctx, _opts) do
  # cleanup/rollback
  {:ok, %{compensated: true, original_error: error}}
end
```

Notes:
- Hooks are optional, overridable
- `on_error/4` only used if compensation enabled

### Slide 5: Output validation

Content:
- Validate the shape of results with `output_schema`
- Extra output fields are allowed

Code:
```elixir
# source: projects/jido_action/test/support/test_actions.ex
defmodule JidoTest.TestActions.OutputSchemaAction do
  use Jido.Action,
    name: "output_schema_action",
    schema: [input: [type: :string, required: true]],
    output_schema: [
      result: [type: :string, required: true],
      length: [type: :integer, required: true]
    ]
  def run(%{input: input}, _ctx) do
    {:ok, %{result: String.upcase(input), length: String.length(input), extra: "ok"}}
  end
end
```

Notes:
- `Jido.Exec` validates outputs after `run/2`
- Unknown fields are preserved

### Slide 6: Execute actions with Jido.Exec

Content:
- Synchronous run with params/context
- Validation errors are structured

Code:
```elixir
# source: projects/jido_action/README.md
# Sync execution
{:ok, result} = Jido.Exec.run(MyApp.Actions.GreetUser, %{name: "Alice"})
# Validation error
{:error, reason} = Jido.Exec.run(MyApp.Actions.GreetUser, %{invalid: "params"})
```

Notes:
- Context can be a map; merged into `context` arg
- Use `log_level:` to tune logging

### Slide 7: Asynchronous execution

Content:
- `run_async/4` returns ref; use `await/2`
- Cancel with `cancel/1`

Code:
```elixir
# source: projects/jido_action/test/jido_action/examples/user_registration_workflow_test.exs
async_ref = Jido.Exec.run_async(JidoTest.TestActions.FormatUser, %{name: "John", email: "a@b", age: 30})
{:ok, result} = Jido.Exec.await(async_ref)
```

Notes:
- Supervised by `Jido.Action.TaskSupervisor`
- Prefer async for long I/O

### Slide 8: Instructions: composing workflows

Content:
- Normalize modules/tuples into `Instruction` structs
- Share context across steps

Code:
```elixir
# source: projects/jido_action/lib/jido_instruction.ex
{:ok, instructions} = Jido.Instruction.normalize([
  MyApp.Actions.ValidateUser,
  {MyApp.Actions.ProcessOrder, %{priority: "high"}}
], %{tenant_id: "123"})
```

Notes:
- Supports module, {module, params}, or full struct
- Use with planners/agents

### Slide 9: Chain actions sequentially

Content:
- Compose with `Jido.Exec.Chain.chain/3`
- Merge step outputs into params

Code:
```elixir
# source: projects/jido_action/test/jido_action/examples/user_registration_workflow_test.exs
{:ok, result} = Jido.Exec.Chain.chain([
  JidoTest.TestActions.FormatUser,
  JidoTest.TestActions.EnrichUserData,
  JidoTest.TestActions.NotifyUser
], %{name: "John", email: "john@example.com", age: 30})
```

Notes:
- `{:interrupted, params}` if stopped via interrupt check
- Pass `context:` and options per chain

### Slide 10: Workflow Action (DSL)

Content:
- Build an action that runs a step list
- Supports step, branch, converge, parallel

Code:
```elixir
# source: projects/jido_action/lib/jido_tools/workflow.ex
defmodule MyWorkflow do
  use Jido.Tools.Workflow,
    name: "my_workflow",
    description: "Demo workflow",
    workflow: [
      {:step, [name: "s1"], [{JidoTest.TestActions.FormatUser, []}]},
      {:branch, [name: "cond"], [true,
        {:step, [name: "t"], [{JidoTest.TestActions.EnrichUserData, []}]},
        {:step, [name: "f"], [{JidoTest.TestActions.NotifyUser, []}]}
      ]}
    ]
end
```

Notes:
- Default `execute_step/3` handles common cases
- Override for dynamic conditions

### Slide 11: Error handling and compensation

Content:
- Structured errors via `Jido.Action.Error`
- Enable compensation and implement `on_error/4`

Code:
```elixir
# source: projects/jido_action/README.md
defmodule RobustAction do
  use Jido.Action,
    name: "robust_action",
    compensation: [enabled: true, max_retries: 3]
  def run(_params, _ctx), do: {:error, Jido.Action.Error.execution_error("boom")}
  def on_error(_failed, error, _ctx, _opts), do: {:ok, %{compensated: true, original_error: error}}
end
```

Notes:
- `Jido.Exec` routes errors to `on_error/4` when enabled
- Return `{:ok, map}` to report compensation outcome

### Slide 12: Retries, timeouts, cancellation

Content:
- Built-in retries with exponential backoff
- Timeouts for `run/4` and `await/2`

Code:
```elixir
# source: projects/jido_action/lib/jido_action/exec.ex
# Retry with backoff
{:error, _} = Jido.Exec.run(MyAction, %{p: 1}, %{}, max_retries: 3, backoff: 250)
# Timeout on async await
ref = Jido.Exec.run_async(JidoTest.TestActions.DelayAction, %{delay: 5_000})
{:error, _} = Jido.Exec.await(ref, 100)
```

Notes:
- Retry policy: `:max_retries`, `:backoff` (ms)
- Use small `timeout` in tests; larger in prod

### Slide 13: Turn actions into AI tools

Content:
- `to_tool/0` exports tool definition
- `Jido.Action.Tool.execute_action/3` adapts JSON args

Code:
```elixir
# source: projects/jido_action/guides/ai-integration.md
{:ok, result} = Jido.Action.Tool.execute_action(
  MyApp.Actions.ProcessData,
  %{"data" => "input from AI"},
  %{}
)
```

Notes:
- Handles string-key JSON and type conversion
- Pair with LLMs that support function calling

### Slide 14: Observability and action metadata

Content:
- `context.action_metadata` exposes name/vsn/tags
- Telemetry hooks emitted by Exec

Code:
```elixir
# source: projects/jido_action/test/support/test_actions.ex
defmodule JidoTest.TestActions.MetadataAction do
  use Jido.Action, name: "metadata_action", vsn: "87.52.1", schema: []
  def run(_params, ctx), do: {:ok, %{metadata: ctx.action_metadata}}
end
```

Notes:
- Attach handlers to `[:jido, :action]` spans for metrics
- Useful for logging, tracing, auditing

### Slide 15: End-to-end: packaged chain as action

Content:
- Wrap a chain into a single action module
- Keep business flows testable and reusable

Code:
```elixir
# source: projects/jido_action/test/support/test_actions.ex
defmodule JidoTest.TestActions.FormatEnrichNotifyUserChain do
  use Jido.Action, name: "format_enrich_notify_user_chain",
    schema: [name: [type: :string, required: true], email: [type: :string, required: true], age: [type: :integer, required: true]]
  def run(params, _ctx) do
    Jido.Exec.Chain.chain([
      JidoTest.TestActions.FormatUser,
      JidoTest.TestActions.EnrichUserData,
      JidoTest.TestActions.NotifyUser
    ], params)
  end
end
```

Notes:
- `Chain.chain/3` merges intermediate results
- Tests assert user fields and notification state

### Slide 16: Integration with agents and signals

Content:
- Agents register actions as tools (`to_tool/0`)
- Agents call actions via `Tool.execute_action/3` with AI-provided args

Code:
```elixir
# source: projects/jido_action/guides/ai-integration.md
tool_def = MyApp.Actions.SearchUsers.to_tool()
{:ok, res} = Jido.Action.Tool.execute_action(MyApp.Actions.SearchUsers, %{"query" => "alice"}, %{})
```

Notes:
- Actions are the execution surface for agents
- Plans/instructions map to sequences of actions
