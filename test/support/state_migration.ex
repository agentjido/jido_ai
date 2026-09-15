defmodule Jido.AI.Test.StateMigration.Update do
  @moduledoc false
  use Jido.Action,
    name: "state_update",
    schema: Zoi.object(%{kind: Zoi.string(), value: Zoi.integer() |> Zoi.default(1)})

  def run(%{kind: kind, value: value}, context) do
    send(context.observer, {:state_tool, self(), kind, value, context.agent_state})

    if kind == "hold",
      do:
        (receive do
           :release -> :ok
         end)

    state = context.agent_state

    case kind do
      "hold" ->
        {:ok, %{value: value}}

      "read" ->
        {:ok, Map.take(state, [:count, :data])}

      "invalid" ->
        {:ok, %{}, [Jido.AI.Effects.state(%{state | count: "invalid"})]}

      "protected" ->
        {:ok, %{}, [Jido.AI.Effects.state(%{state | requests: %{"forged" => %{status: :completed}}})]}

      "update" ->
        next = %{state | count: value, data: Map.merge(state.data, %{status: :running, iteration: value})}
        {:ok, %{count: value}, [Jido.AI.Effects.state(next)]}
    end
  end
end

defmodule Jido.AI.Test.StateMigration.Double do
  @moduledoc false
  use Jido.Action, name: "state_double", schema: Zoi.object(%{value: Zoi.integer()})
  def run(%{value: value}, _), do: {:ok, %{result: value * 2}}
end

defmodule Jido.AI.Test.StateMigration.Change do
  @moduledoc false
  use Jido.Action, name: "state_change", schema: Zoi.object(%{label: Zoi.string()})
  def run(%{label: label}, context), do: {:ok, %{context.agent_state | label: label}}
end

defmodule Jido.AI.Test.StateMigration.Agent do
  @moduledoc false
  use Jido.Agent, name: "state_migration", extensions: [Jido.AI.DSL]

  agent do
    schema(
      Zoi.object(%{
        answer: Zoi.any() |> Zoi.default(nil),
        count: Zoi.integer() |> Zoi.default(0),
        label: Zoi.string() |> Zoi.default("initial"),
        data: Zoi.map() |> Zoi.default(%{}),
        messages: Jido.AI.Conversation.schema()
      })
    )

    ai :assistant do
      instructions("State test")
      effect_policy(%{allow: [Jido.AI.Effects.State]})

      models do
        model(:answer, Jido.AI.Test.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      tools do
        action(Jido.AI.Test.StateMigration.Update, as: :state_update, forward_context: [:observer, :agent_state])
      end

      requests do
        mode(:session)
      end

      memory do
        history(:messages)
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.react.query", ai(:assistant))
    route("state.change", Jido.AI.Test.StateMigration.Change)
  end
end
