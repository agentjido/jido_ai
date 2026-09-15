Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.CombinationsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias Jido.AgentServer, as: Server
  alias JidoAITest.Authoring.Agents.Corpus
  alias JidoAITest.Authoring.Agents.Fixtures.Mixed
  # The fixture is deliberately compiled only when selected tests run.
  @compile {:no_warn_undefined, Mixed}

  setup do
    JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("mixed.exs"))
    jido = :"authoring_combinations_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  for form <- [:module, :builder, :codec] do
    @tag form: form
    test "#{form}: turn/session profiles and two instances keep model, prompt and state separate", %{
      jido: jido,
      form: form
    } do
      definition = definition(form)

      first_mock =
        start_supervised!(
          {MockLLM, script: [%{reply: {:text, "Turn"}}, %{reply: {:text, "Review"}}, %{reply: {:text, "Cleared"}}]},
          id: :first_provider
        )

      second_mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Other"}}]}, id: :second_provider)
      {:ok, first} = Jido.start_agent(jido, definition)
      {:ok, second} = Jido.start_agent(jido, definition)
      assert {:ok, _} = Jido.AI.set_system_prompt(first, "Changed", profile: :assistant)
      assert {:ok, "Turn"} = Mixed.ask(first, "Turn query", profile: :assistant, context: context(first_mock))
      assert {:ok, "Review"} = Mixed.ask_sync(first, "Review query", profile: :reviewer, context: context(first_mock))
      assert Server.agent(first).state.reply == "Turn"
      assert Server.agent(first).state.review == "Review"
      assert {:ok, _} = Jido.AI.set_system_prompt(first, "", profile: :assistant)
      assert {:ok, "Cleared"} = Mixed.ask(first, "Clear query", profile: :assistant, context: context(first_mock))
      assert {:ok, "Other"} = Mixed.ask(second, "Other query", profile: :assistant, context: context(second_mock))
      assert Server.agent(second).state.review == ""
      assert is_nil(Server.agent(second).state.messages)
      assert Server.agent(second).state.jido_ai_config == %{}
      assert %{remaining: [], unexpected: [], requests: [turn, review, cleared]} = MockLLM.report(first_mock)
      assert turn.body["model"] == "gpt-4o-mini"
      assert review.body["model"] == "gpt-4o"
      assert system(turn) == ["Changed"]
      assert system(review) == ["Session instruction"]
      assert system(cleared) == []

      assert Enum.filter(review.body["messages"], &(&1["role"] == "user")) == [
               %{"role" => "user", "content" => "Review query"}
             ]

      assert %{remaining: [], unexpected: [], requests: [other]} = MockLLM.report(second_mock)
      assert system(other) == ["Turn instruction"]
    end
  end

  test "generated cancel ends held work and allows a new request", %{jido: jido} do
    mock =
      start_supervised!(
        {MockLLM, observer: self(), script: [%{reply: {:wait, :held, {:text, "unused"}}}, %{reply: {:text, "Next"}}]}
      )

    {:ok, server} = Jido.start_agent(jido, Mixed)
    assert {:ok, request} = Mixed.ask(server, "Cancel", profile: :reviewer, context: context(mock))
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 5_000
    monitor = Process.monitor(provider)
    assert :ok = Mixed.cancel(server, request_id: request.id, reason: :test_cancel)
    assert {:error, {:cancelled, :test_cancel}} = Mixed.await(request, timeout: 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 5_000
    assert Server.agent(server).state.review == ""
    assert {:ok, "Next"} = Mixed.ask_sync(server, "Next", profile: :reviewer, context: context(mock))
    assert %{remaining: [], unexpected: [], requests: [_, _]} = MockLLM.report(mock)
  end

  test "generated steer rejects stale input and consumes accepted input", %{jido: jido} do
    mock =
      start_supervised!(
        {MockLLM, observer: self(), script: [%{reply: {:wait, :held, {:text, "First"}}}, %{reply: {:text, "Revised"}}]}
      )

    {:ok, server} = Jido.start_agent(jido, Mixed)
    assert {:ok, request} = Mixed.ask(server, "First query", profile: :reviewer, context: context(mock))
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 5_000
    assert {:error, _} = Mixed.steer(server, "Stale", expected_request_id: "wrong")
    assert {:ok, _} = Mixed.steer(server, "Revised query", expected_request_id: request.id)
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Revised"} = Mixed.await(request, timeout: 5_000)
    assert %{remaining: [], unexpected: [], requests: [_, last]} = MockLLM.report(mock)
    texts = last.body["messages"] |> Enum.filter(&(&1["role"] == "user")) |> Enum.map(& &1["content"])
    assert texts == ["First query", "Revised query"]
  end

  test "turn profiles reject streaming before starting work", %{jido: jido} do
    mock = start_supervised!({MockLLM, script: []})
    {:ok, server} = Jido.start_agent(jido, Mixed)
    before = Server.snapshot(server)

    assert {:error, %Jido.AI.Error.Validation.Invalid{field: "requests.streaming"}} =
             Mixed.ask_stream(server, "No", profile: :assistant, context: context(mock))

    assert Server.snapshot(server) === before
    assert MockLLM.report(mock).requests == []
  end

  defp context(mock), do: %{ai: Map.new([:assistant, :reviewer], &{&1, %{options: MockLLM.options(mock)}})}

  defp system(request),
    do: request.body["messages"] |> Enum.filter(&(&1["role"] == "system")) |> Enum.map(& &1["content"])

  defp definition(:module), do: Mixed.definition()
  defp definition(:builder), do: Jido.Agent.Builder.new(Mixed) |> Jido.Agent.Builder.build!()

  defp definition(:codec) do
    {:ok, doc, registry} = Jido.Agent.Codec.encode(Mixed.definition())
    {:ok, value} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(doc)), registry)
    value
  end
end
