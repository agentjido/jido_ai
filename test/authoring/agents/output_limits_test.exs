Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.OutputLimitsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias JidoAITest.Authoring.Agents.Corpus

  setup do
    jido = :"authoring_output_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  for form <- [:lowered, :builder, :codec], repair? <- [true, false] do
    @tag form: form, repair?: repair?
    test "#{form}/repair=#{repair?}: invalid structured output respects the repair budget", ctx do
      spec = Corpus.load!(:structured)

      profiles =
        Enum.map(
          spec.profiles,
          &Map.put(&1, :result, %{
            into: :reply,
            schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}),
            max_repairs: 1
          })
        )

      {:ok, source} = Jido.AI.Authoring.lower(spec.attrs, profiles)
      answer = if ctx.repair?, do: "Repaired", else: ""

      mock =
        start_supervised!(
          {MockLLM,
           script: [
             %{reply: {:object, %{answer: ""}}},
             %{reply: {:object, %{answer: answer}}},
             %{reply: {:object, %{answer: "Next"}}}
           ]}
        )

      {:ok, server} = Jido.start_agent(ctx.jido, transport(source, ctx.form))
      result = call(server, mock)

      if ctx.repair? do
        assert {:ok, agent} = result
        assert agent.state.reply == %{answer: "Repaired"}
      else
        assert {:error, _} = result
        assert Jido.AgentServer.agent(server).state === spec.initial
      end

      assert length(MockLLM.report(mock).requests) == 2
      assert {:ok, next} = call(server, mock)
      assert next.state.reply == %{answer: "Next"}
      assert %{remaining: [], unexpected: [], requests: [_, _, _]} = MockLLM.report(mock)
    end
  end

  for form <- [:lowered, :codec] do
    @tag form: form
    test "#{form}: model call limit prevents a second provider call after a tool", %{jido: jido, form: form} do
      spec = Corpus.load!(:tool)
      profiles = Enum.map(spec.profiles, &Map.put(&1, :controls, %{timeout: 5_000, max_model_calls: 1}))
      {:ok, source} = Jido.AI.Authoring.lower(spec.attrs, profiles)

      mock =
        start_supervised!(
          {MockLLM, script: [%{reply: {:tools, [%{id: "bounded", name: "double", arguments: %{value: 3}}]}}]}
        )

      {:ok, server} = Jido.start_agent(jido, transport(source, form))
      assert {:error, _} = call(server, mock)
      assert_received {:authoring_tool, 3}
      assert Jido.AgentServer.agent(server).state === spec.initial
      assert %{remaining: [], unexpected: [], requests: [_]} = MockLLM.report(mock)
    end
  end

  test "session deadline closes held provider work and a later request succeeds", %{jido: jido} do
    spec = Corpus.load!(:session)
    profiles = Enum.map(spec.profiles, &Map.put(&1, :controls, %{timeout: 500}))
    {:ok, source} = Jido.AI.Authoring.lower(spec.attrs, profiles)

    mock =
      start_supervised!(
        {MockLLM,
         observer: self(), script: [%{reply: {:wait, :deadline, {:text, "unused"}}}, %{reply: {:text, "Next"}}]}
      )

    {:ok, server} = Jido.start_agent(jido, source)
    assert {:ok, _} = call(server, mock, "timed")
    assert_receive {:mock_llm_waiting, ^mock, :deadline, provider}, 5_000
    monitor = Process.monitor(provider)
    assert {:ok, record} = Jido.AI.Session.await(server, "timed", 5_000)
    assert record.status in [:failed, :timeout]
    assert record.error != nil
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 5_000
    assert Jido.AgentServer.agent(server).state.reply == ""
    assert {:ok, _} = call(server, mock, "next")
    assert {:ok, %{status: :completed, result: "Next"}} = Jido.AI.Session.await(server, "next", 5_000)
    assert %{remaining: [], unexpected: [], requests: [_, _]} = MockLLM.report(mock)
  end

  defp call(server, mock, id \\ "request"),
    do:
      Jido.AgentServer.call(
        server,
        Jido.Signal.new!("case.assistant", %{query: "Help", request_id: id}, source: "/authoring"),
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
