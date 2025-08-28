### Slide 1: Jido overview

Content:
- Toolkit for autonomous, distributed Elixir agents
- Core: agents, actions, signals, sensors, skills

Code:
```elixir
# source: projects/jido/lib/jido.ex
@spec start_link() :: Supervisor.on_start()
def start_link do
  unquote(__MODULE__).ensure_started(__MODULE__)
end

@spec ensure_started(module()) :: Supervisor.on_start()
def ensure_started(jido_module) do
  config = jido_module.config()
  Jido.Supervisor.start_link(jido_module, config)
end
```

Notes:
- Supervisable entrypoint via `use Jido`
- Central supervisor starts registries and runtime

### Slide 2: Core building blocks

Content:
- Agents execute actions via runners
- Sensors emit signals; skills extend behavior

Code:
```elixir
# source: projects/jido/mix.exs
groups_for_modules: [
  Core: [Jido, Jido.Action, Jido.Agent, Jido.Agent.Server, Jido.Instruction, Jido.Sensor, Jido.Workflow],
  "Actions: Directives": [Jido.Agent.Directive, Jido.Actions.Directives],
  Skills: [Jido.Skill],
  Examples: [Jido.Sensors.Cron, Jido.Sensors.Heartbeat],
  Utilities: [Jido.Discovery, Jido.Error, Jido.Supervisor, Jido.Util]
]
```

Notes:
- Orientation to where concepts live
- Workflow = instruction sequences, executed by runners

### Slide 3: Stateless vs stateful

Content:
- Stateless: compile-time agent struct for planning
- Stateful: runtime GenServer manages execution/state

Code:
```elixir
# source: projects/jido/lib/jido/agent.ex
typedstruct do
  field(:id, String.t())
  field(:name, String.t())
  field(:description, String.t())
  field(:category, String.t())
  field(:tags, [String.t()])
  field(:vsn, String.t())
  field(:schema, NimbleOptions.schema())
  field(:actions, [module()], default: [])
  field(:runner, module())
  field(:dirty_state?, boolean(), default: false)
  field(:pending_instructions, :queue.queue(instruction()))
  field(:state, map(), default: %{})
  field(:result, term(), default: nil)
end
```

Notes:
- Plan with the struct; run via `Jido.Agent.Server`
- Server enforces queue, transitions, directives

### Slide 4: Define an agent

Content:
- Declarative schema; register actions
- Extensible via actions and skills

Code:
```elixir
# source: projects/jido/test/support/test_agent.ex
defmodule JidoTest.TestAgents.TaskManagementAgent do
  use Jido.Agent,
    name: "task_management_agent",
    description: "Tests task management functionality",
    category: "test",
    tags: ["test", "tasks"],
    vsn: "1.0.0",
    actions: [
      Jido.Actions.Tasks.CreateTask,
      Jido.Actions.Tasks.UpdateTask,
      Jido.Actions.Tasks.ToggleTask,
      Jido.Actions.Tasks.DeleteTask
    ],
    schema: [tasks: [type: :map, default: %{}]]
end
```

Notes:
- Actions implement `Jido.Action`; schema validated with NimbleOptions
- Agent struct holds queue, state, metadata

### Slide 5: End-to-end example (plan → run → result)

Content:
- Queue actions then execute
- Results stored on agent; directives apply state

Code:
```elixir
# source: projects/jido/test/jido/agent/examples/user_registration_agent_test.exs
{:ok, planned_agent} =
  UserAgent.plan(initial_agent, [
    {FormatUser, initial_agent.state},
    EnrichUserData
  ])

{:ok, _result_agent, _directives} =
  UserAgent.run(planned_agent, apply_state: true, runner: Jido.Runner.Chain)
```

Notes:
- `plan/3` validates and enqueues; `run/2` uses a runner
- Chain runner merges results across actions

### Slide 6: Planning instructions (API)

Content:
- Normalize modules/tuples to instructions
- Validate actions are registered

Code:
```elixir
# source: projects/jido/lib/jido/agent.ex
@spec plan(t() | Jido.server(), instructions(), map()) :: agent_result()
def plan(agent, instructions, context \\ %{})

def plan(%__MODULE__{} = agent, instructions, context) do
  with {:ok, instruction_structs} <- Instruction.normalize(instructions, context),
       :ok <- Instruction.validate_allowed_actions(instruction_structs, agent.actions),
       {:ok, agent} <- on_before_plan(agent, nil, %{}),
       {:ok, agent} <- enqueue_instructions(agent, instruction_structs) do
    OK.success(%{agent | dirty_state?: true})
  else
    {:error, %{details: %{actions: actions}} = error} ->
      %{error | message: "Action: #{actions |> Enum.join(", ")} not registered with agent #{__MODULE__.name()}"}
      |> OK.failure()
  end
end
```

Notes:
- Guards against unregistered actions
- Hook: `on_before_plan/3`

### Slide 7: Running instructions (Simple runner)

Content:
- Dequeues one instruction and executes
- Applies directives optionally

Code:
```elixir
# source: projects/jido/lib/jido/runner/simple.ex
@impl true
@spec run(Jido.Agent.t(), run_opts()) :: run_result()
def run(%{pending_instructions: instructions} = agent, opts \\ []) do
  case :queue.out(instructions) do
    {{:value, %Instruction{} = instruction}, remaining} ->
      agent = %{agent | pending_instructions: remaining}
      execute_instruction(agent, instruction, opts)

    {:empty, _} ->
      {:ok, agent, []}
  end
end
```

Notes:
- Merges runner opts with instruction opts
- Result set on `agent.result`

### Slide 8: Running instructions (Chain runner)

Content:
- Sequential execution, optional result merging
- Accumulates directives and applies at end

Code:
```elixir
# source: projects/jido/lib/jido/runner/chain.ex
@impl true
@spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
def run(%{pending_instructions: instructions} = agent, opts \\ []) do
  case :queue.to_list(instructions) do
    [] -> {:ok, %{agent | pending_instructions: :queue.new()}, []}
    [_ | _] = instructions_list -> execute_chain(agent, instructions_list, opts)
  end
end
```

Notes:
- `merge_results` feeds prior output into next action
- Defers directive application to end

### Slide 9: End-to-end data flow (diagram)

Content:
- Signal → Agent Server → Runner → Action → Directives → State/Output
- Events and outputs emitted via `Server.Signal`

Code:
```mermaid
flowchart LR
  S[Sensor or Client Signal] -->|enqueue| Q[Agent Server Queue]
  Q --> R[Runner]
  R --> A[Action]
  A -->|result| D{Directives?}
  D -- yes -->|apply| ST[Agent State]
  D -- no --> ST
  R --> O[Output Signal]
  S -. events .-> E[Server Events]
```

Notes:
- Server enqueues signals, processes via runner
- Directives mutate state, spawn/kill, enqueue

### Slide 10: Signals and routing

Content:
- Namespaced command/event/output types
- Helper builds typed subjects and IDs

Code:
```elixir
# source: projects/jido/lib/jido/agent/server_signal.ex
def type({:cmd, :state}), do: @cmd_base ++ ["state"]
def type({:cmd, :plan}),  do: @cmd_base ++ ["plan"]
def type({:cmd, :run}),   do: @cmd_base ++ ["run"]
def type({:event, :started}), do: @event_base ++ ["started"]
def type({:event, :queue_overflow}), do: @event_base ++ ["queue", "overflow"]
def type({:out, :instruction_result}), do: @output_base ++ ["instruction", "result"]

def cmd_signal(:plan, %ServerState{} = state, params, ctx),
  do: build(state, %{type: type({:cmd, :plan}), data: params})
```

Notes:
- Joined with dots, e.g., `jido.agent.cmd.plan`
- `build/2` injects subject and dispatch target

### Slide 11: Sensors (define and emit)

Content:
- GenServer that produces `Jido.Signal`
- Validated options and retained last values

Code:
```elixir
# source: projects/jido/test/support/test_sensors.ex
defmodule JidoTest.TestSensors.TestSensor do
  use Jido.Sensor,
    name: "test_sensor",
    schema: [test_param: [type: :integer, default: 0]]

  def deliver_signal(state) do
    {:ok, Jido.Signal.new(%{type: "test_signal", data: %{value: state.config.test_param}})}
  end
end
```

Notes:
- `mount/1` initializes state; `on_before_deliver/2` can veto
- Dispatch configured via sensor `:target`

### Slide 12: Sensor → Agent integration

Content:
- Agent injects its PID into sensor targets
- Sensors run under agent’s DynamicSupervisor

Code:
```elixir
# source: projects/jido/lib/jido/agent/server_sensors.ex
sensors_with_target = prepare_sensor_specs(sensors, agent_pid)
updated_opts =
  opts
  |> Keyword.update(:child_specs, sensors_with_target, fn existing_specs ->
    (List.wrap(existing_specs) ++ sensors_with_target)
    |> Enum.uniq()
  end)
```

Notes:
- Sensors registered as children; signals route to agent
- Works with single or keyword `:target` configs

### Slide 13: Skills (extend agents)

Content:
- Encapsulate routing/handlers and optional child processes
- Isolated config via `opts_key` and schema

Code:
```elixir
# source: projects/jido/test/support/test_skills.ex
defmodule JidoTest.TestSkills.TestSkill do
  use Jido.Skill,
    name: "test_skill",
    opts_key: :test_skill,
    signal_patterns: ["test.skill.**"]

  def handle_signal(signal, _skill), do: {:ok, %{signal | data: Map.put(signal.data, :skill_handled, true)}}
  def transform_result(_signal, result, _skill), do: {:ok, Map.put(result, :skill_processed, true)}
end
```

Notes:
- Skills can add actions and router entries
- Provide `child_spec/1` for needed processes

### Slide 14: High-level APIs

Content:
- Locate agents and inspect state
- Clone running agents with same config

Code:
```elixir
# source: projects/jido/lib/jido.ex
@spec get_agent(String.t() | atom(), keyword()) :: {:ok, pid()} | {:error, :not_found}
def get_agent(id, opts \\ []) do
  registry = opts[:registry] || Jido.Registry
  case Registry.lookup(registry, id) do
    [{pid, _}] -> {:ok, pid}
    [] -> {:error, :not_found}
  end
end
```

Notes:
- Use with `Jido.Agent.Server.call/cast` and `Jido.get_agent_state/1`
- Supports custom registries

### Slide 15: Directives apply state/results

Content:
- Actions can emit state modifications or server directives
- Directive application happens in runner

Code:
```elixir
# source: projects/jido/lib/jido/actions/tasks.ex
@impl true
def run(params, context) do
  task = Task.new(params.title, params.deadline)
  tasks = Map.get(context.state, :tasks, %{})
  updated_tasks = Map.put(tasks, task.id, task)
  {:ok, task, [%StateModification{op: :set, path: [:tasks], value: updated_tasks}]}
end
```

Notes:
- `StateModification` updates agent state atomically
- Other directives: enqueue, register/deregister, spawn/kill

### Slide 16: Workspace configuration (JIDO_WORKSPACE)

Content:
- Local dev can use in-repo deps via `JIDO_WORKSPACE=1`
- Publishing: unset env to ensure Hex deps

Code:
```elixir
# source: projects/jido/mix.exs
defp workspace? do
  System.get_env("JIDO_WORKSPACE") in ["1", "true"]
end

defp ws_dep(app, rel_path, remote_opts, extra_opts \\ []) do
  if workspace?() and File.dir?(Path.expand(rel_path, __DIR__)) do
    {app, [path: rel_path, override: true] ++ extra_opts}
  else
    {app, remote_opts ++ extra_opts}
  end
end
```

Notes:
- Toggle path deps for `jido_action`/`jido_signal`
- Safety: Unset `JIDO_WORKSPACE` when publishing Hex
