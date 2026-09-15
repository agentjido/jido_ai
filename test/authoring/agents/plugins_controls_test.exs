Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.PluginsControlsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias JidoAITest.Authoring.Agents.{Corpus, Fixtures}

  setup do
    JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("composition.exs"))
    jido = :"authoring_plugins_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  for form <- [:lowered, :builder, :codec], reverse? <- [false, true] do
    @tag form: form, reverse?: reverse?
    test "#{form}/reverse=#{reverse?}: custom Plugin order remains visible after AI execution", ctx do
      spec = Corpus.load!(:simple)
      plugins = [{Fixtures.CounterPlugin, []}, {Fixtures.MirrorPlugin, []}]
      plugins = if ctx.reverse?, do: Enum.reverse(plugins), else: plugins
      {:ok, source} = Jido.AI.Authoring.lower(%{spec.attrs | plugins: plugins}, spec.profiles)
      definition = transport(source, ctx.form)
      assert definition === source
      mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Done"}}]})
      {:ok, server} = Jido.start_agent(ctx.jido, definition)
      before = Jido.AgentServer.agent(server).state
      assert {:ok, agent} = call(server, mock)
      assert agent.state.reply == "Done"
      assert agent.state.counter > before.counter
      assert agent.state.mirror == agent.state.counter - if(ctx.reverse?, do: 1, else: 0)
      assert agent.state.jido_ai_config == %{}
      assert %{remaining: [], unexpected: [], requests: [_]} = MockLLM.report(mock)
    end
  end

  for form <- [:lowered, :builder, :codec] do
    @tag form: form
    test "#{form}: operation control blocks an authored tool before its Action runs", %{jido: jido, form: form} do
      spec = Corpus.load!(:tool)

      profiles =
        Enum.map(
          spec.profiles,
          &Map.put(&1, :controls, %{timeout: 5_000, operation: [%{module: Fixtures.DenyTool, when: %{name: "double"}}]})
        )

      {:ok, source} = Jido.AI.Authoring.lower(spec.attrs, profiles)

      mock =
        start_supervised!(
          {MockLLM, script: [%{reply: {:tools, [%{id: "denied", name: "double", arguments: %{value: 3}}]}}]}
        )

      {:ok, server} = Jido.start_agent(jido, transport(source, form))
      assert {:error, _} = call(server, mock)
      assert_received :authoring_tool_denied
      refute_received {:authoring_tool, _}
      assert Jido.AgentServer.agent(server).state === spec.initial
      assert %{remaining: [], unexpected: [], requests: [_]} = MockLLM.report(mock)
    end
  end

  test "tool execution failure reaches the model as a tool result and permits recovery", %{jido: jido} do
    spec = Corpus.load!(:simple)

    profiles =
      Enum.map(
        spec.profiles,
        &Map.put(&1, :tools, [%{name: "failing_tool", target: Fixtures.FailingTool, forward_context: :public}])
      )

    {:ok, definition} = Jido.AI.Authoring.lower(spec.attrs, profiles)

    mock =
      start_supervised!(
        {MockLLM,
         script: [
           %{reply: {:tools, [%{id: "failed", name: "failing_tool", arguments: %{}}]}},
           %{reply: {:text, "Next"}}
         ]}
      )

    {:ok, server} = Jido.start_agent(jido, definition)
    assert {:ok, agent} = call(server, mock)
    assert_received :authoring_tool_failed
    assert agent.state === %{spec.initial | reply: "Next"}
    assert %{remaining: [], unexpected: [], requests: [_, last]} = MockLLM.report(mock)

    assert Enum.any?(
             last.body["messages"],
             &(&1["role"] == "tool" and &1["tool_call_id"] == "failed" and
                 String.contains?(&1["content"], "deliberate_tool_failure"))
           )
  end

  defp call(server, mock),
    do:
      Jido.AgentServer.call(server, Jido.Signal.new!("case.assistant", %{query: "Help"}, source: "/authoring"),
        context: %{observer: self(), ai: %{assistant: %{options: MockLLM.options(mock)}}},
        timeout: 10_000
      )

  defp transport(value, :lowered), do: value

  defp transport(value, :builder),
    do: value |> Map.from_struct() |> Map.drop([:id, :state]) |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build!()

  defp transport(value, :codec) do
    {:ok, doc, registry} = Jido.Agent.Codec.encode(value)
    {:ok, decoded} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(doc)), registry)
    decoded
  end
end
