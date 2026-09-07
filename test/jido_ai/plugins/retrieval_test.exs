defmodule Jido.AI.Plugins.RetrievalTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Plugins.Retrieval
  alias Jido.AI.Retrieval.Store

  setup do
    start_supervised!({Store, []})
    :ok
  end

  defp command(data, opts \\ []) do
    definition =
      Jido.Agent.new!(%{
        name: "retrieval_test",
        schema: Zoi.object(%{}),
        plugins: [{Retrieval, opts}]
      })

    agent = Jido.Agent.instantiate!(definition, id: "agent_weather")

    %Jido.Agent.Command{
      agent: agent,
      context: %{},
      signal: Jido.Signal.new!("chat.message", data, source: "/test")
    }
  end

  test "live admission enriches the prompt and retains snippet metadata" do
    Store.upsert("weather", %{
      id: "m1",
      text: "Tokyo weather forecast",
      metadata: %{tag: "weather"}
    })

    assert {:ok, %{signal: enriched}} =
             Retrieval.admit(nil, command(%{prompt: "Tokyo weather"}, namespace: "weather"), [])

    assert enriched.data.prompt =~ "Relevant memory:"
    assert [%{id: "m1", metadata: %{tag: "weather"}}] = enriched.data.retrieval.snippets
  end

  for key <- [:disable_retrieval, "disable_retrieval"] do
    test "live admission keeps the request when #{key |> inspect()} is true" do
      cmd = command(Map.put(%{prompt: "Tokyo weather"}, unquote(key), true))
      assert {:ok, ^cmd} = Retrieval.admit(nil, cmd, [])
    end
  end

  test "declared state retains configured namespace and recall defaults" do
    cmd = command(%{}, namespace: "team_weather", top_k: 5, max_snippet_chars: 300)

    assert %{namespace: "team_weather", top_k: 5, max_snippet_chars: 300} =
             cmd.agent.state.retrieval
  end

  test "live admission resolves an omitted namespace from the current Agent id" do
    Store.upsert("agent_weather", %{id: "m1", text: "Tokyo weather forecast"})

    assert {:ok, %{signal: enriched}} =
             Retrieval.admit(nil, command(%{prompt: "Tokyo weather"}), [])

    assert enriched.data.retrieval.namespace == "agent_weather"
  end

  test "standalone namespace resolution has a default without an Agent id" do
    assert Jido.AI.Actions.Retrieval.Request.namespace(%{}) == "default"
  end
end
