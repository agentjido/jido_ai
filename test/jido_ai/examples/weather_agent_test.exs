defmodule Jido.AI.Examples.WeatherAgentTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Examples.{ReActDemoAgent, WeatherAgent}

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido.Registry)) do
      start_supervised!({Registry, keys: :unique, name: Jido.Registry})
    end

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      {:ok,
       %{
         stream: [ReqLLM.StreamChunk.text("stubbed runtime response")],
         usage: %{input_tokens: 4, output_tokens: 3}
       }}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    :ok
  end

  test "ReActDemoAgent runs ask_sync over runtime adapter" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: ReActDemoAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert {:ok, "stubbed runtime response"} = ReActDemoAgent.ask_sync(pid, "What is 12 * 9?", timeout: 5_000)

    config =
      pid
      |> fetch_agent()
      |> StratState.get(%{})
      |> Map.get(:config, %{})

    assert config.runtime_adapter == true
  end

  test "WeatherAgent helper methods run over runtime adapter" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: WeatherAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert {:ok, "stubbed runtime response"} = WeatherAgent.get_conditions(pid, "Denver", timeout: 5_000)
    assert {:ok, "stubbed runtime response"} = WeatherAgent.get_forecast(pid, "Seattle", timeout: 5_000)

    config =
      pid
      |> fetch_agent()
      |> StratState.get(%{})
      |> Map.get(:config, %{})

    assert config.runtime_adapter == true
  end

  defp fetch_agent(pid) do
    {:ok, server_state} = Jido.AgentServer.state(pid)
    server_state.agent
  end
end
