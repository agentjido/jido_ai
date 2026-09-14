defmodule Jido.AI.Plugins.RetrievalTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Plugins.Retrieval
  alias Jido.AI.Retrieval.Store
  alias ReqLLM.Message.ContentPart

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

  defp admit(command) do
    with {:ok, specs} <- Jido.Plugin.normalize_all(command.agent.plugins),
         {:ok, inputs} <- Jido.Agent.Plugin.prepare(command.agent, command.signal, specs) do
      admission = %Jido.AgentServer.Plugin.Admission{
        plugin: Retrieval,
        agent_id: command.agent.id,
        agent_module: command.agent.module,
        signal: command.signal,
        caller_context: command.context,
        plugin_state: command.agent.state.retrieval,
        prepared_input: inputs[Retrieval].prepared,
        state_version: 0
      }

      Retrieval.AgentServer.admit(nil, admission, [])
    end
  end

  test "live admission enriches the prompt and retains snippet metadata" do
    Store.upsert("weather", %{
      id: "m1",
      text: "Tokyo weather forecast",
      metadata: %{tag: "weather"}
    })

    assert {:ok, enriched} = admit(command(%{prompt: "Tokyo weather"}, namespace: "weather"))

    assert enriched.value =~ "Relevant memory:"
    assert [%{id: "m1", metadata: %{tag: "weather"}}] = enriched.retrieval.snippets
  end

  test "live admission enriches multimodal prompts and preserves every original part" do
    Store.upsert("weather", %{id: "m1", text: "Tokyo weather forecast"})

    image = ContentPart.image_url("https://example.com/tokyo.png")
    query = [ContentPart.text("Tokyo weather"), image]

    assert {:ok, enriched} = admit(command(%{prompt: query}, namespace: "weather"))

    assert [memory_part | ^query] = enriched.value
    assert memory_part.type == :text
    assert memory_part.text =~ "Relevant memory:"
    assert memory_part.text =~ "Tokyo weather forecast"
  end

  for key <- [:disable_retrieval, "disable_retrieval"] do
    test "live admission keeps the request when #{key |> inspect()} is true" do
      cmd = command(Map.put(%{prompt: "Tokyo weather"}, unquote(key), true))
      assert {:ok, nil} = admit(cmd)
      assert {:ok, specs} = Jido.Plugin.normalize_all(cmd.agent.plugins)

      assert {:ok, %{Retrieval => %{prepared: %{store: Store, capability: nil}}}} =
               Jido.Agent.Plugin.prepare(cmd.agent, cmd.signal, specs)
    end
  end

  test "declared state retains configured namespace and recall defaults" do
    cmd = command(%{}, namespace: "team_weather", top_k: 5, max_snippet_chars: 300)

    assert %{namespace: "team_weather", top_k: 5, max_snippet_chars: 300} =
             cmd.agent.state.retrieval
  end

  test "live admission resolves an omitted namespace from the current Agent id" do
    Store.upsert("agent_weather", %{id: "m1", text: "Tokyo weather forecast"})

    assert {:ok, enriched} = admit(command(%{prompt: "Tokyo weather"}))

    assert enriched.retrieval.namespace == "agent_weather"
  end

  test "standalone namespace resolution has a default without an Agent id" do
    assert Jido.AI.Actions.Retrieval.Request.namespace(%{}) == "default"
  end
end
