defmodule Jido.AI.Integration.ReActSteeringIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI

  defmodule SteeringAgent do
    use Jido.AI.Agent, name: "react_steering_agent"

    agent do
      schema Zoi.object(%{last_result: Zoi.any() |> Zoi.default(nil), messages: Jido.AI.Thread.Projection.schema()})

      ai :assistant do
        model("openai:gpt-4o-mini")
        reasoning(:react)
        controls(steering: true)
        memory(history: :messages)
        result(into: :last_result)
      end
    end

    routes do
      route("ai.react.query", ai: :assistant)
    end
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :llm_call_count})
    end)

    :ok
  end

  test "public inject rejects idle agents" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: SteeringAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert {:error, {:rejected, :idle}} = AI.inject(pid, "Programmatic input")
  end
end
