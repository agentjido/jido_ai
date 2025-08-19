# Jido Usage Rules

**Jido** is a functional, OTP-based toolkit for building autonomous, distributed agent systems in Elixir.

## Core Components

### Actions - Pure Functions
```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    description: "Process data",
    schema: [input: [type: :string, required: true]]

  def run(params, _context) do
    {:ok, %{result: String.upcase(params.input)}}
  end
end
```

### Agents - Stateful Orchestrators  
```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent", 
    schema: [status: [type: :atom, default: :idle]],
    actions: [MyAction]
end

# Usage
{:ok, agent} = MyAgent.new()
{:ok, pid} = MyAgent.start_link(agent: agent)
{:ok, result} = MyAgent.cmd(agent, MyAction, %{input: "test"})
```

### Sensors - Real-time Monitoring
```elixir
defmodule MySensor do
  use Jido.Sensor,
    name: "my_sensor",
    schema: [interval: [type: :pos_integer, default: 5000]]

  def mount(opts), do: {:ok, opts}
  def deliver_signal(state) do
    {:ok, Jido.Signal.new(%{topic: "update", payload: get_data()})}
  end
end
```

## Key Patterns

- **Always return tagged tuples**: `{:ok, result}` or `{:error, reason}`
- **Use schemas for validation** in all components
- **Pattern match with function heads** instead of conditionals
- **Actions are pure functions**, Agents manage state
- **Plan before execution**: `Agent.plan(agent, actions) |> Agent.run()`

## Common Operations

```elixir
# Get running agent
{:ok, pid} = Jido.get_agent("agent-id")

# Execute single action
{:ok, result} = Agent.cmd(agent, Action, params)

# Chain multiple actions  
{:ok, agent} = Agent.plan(agent, [
  {Action1, %{input: "data"}},
  {Action2, %{threshold: 0.8}}
])
{:ok, results} = Agent.run(agent)

# Start sensor
{:ok, sensor} = MySensor.start_link(id: "sensor1", target: pid)
```

## Error Handling

```elixir
# In Actions
def run(params, _context) do
  with {:ok, cleaned} <- validate(params.input),
       {:ok, result} <- process(cleaned) do
    {:ok, result}
  else
    {:error, reason} -> {:error, reason}
  end
end

# In Agents - use lifecycle hooks
def on_before_run(agent) do
  if ready?(agent), do: {:ok, agent}, else: {:error, :not_ready}
end
```

## Testing Patterns

```elixir
# Test Actions
test "processes input" do
  assert {:ok, result} = MyAction.run(%{input: "test"}, %{})
  assert result.output == "TEST"
end

# Test Agents
test "executes command" do
  {:ok, agent} = MyAgent.start_link(id: "test")
  assert {:ok, result} = MyAgent.cmd(agent, MyAction, %{input: "test"})
end
```

## Don't

- Skip parameter validation
- Return raw values (use tagged tuples)
- Make Actions stateful
- Create circular dependencies between agents
- Use agents for stateless operations (use Actions)
- Skip error handling
