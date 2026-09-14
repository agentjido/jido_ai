defmodule JidoAI.Examples.QueryAppendTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, State, Token}
  alias JidoAI.Examples.{QueryAppend, CheckpointResume}
  alias JidoAI.Examples.StandaloneAuthoring.{Add, Change, Transform}

  test "append after completion keeps history identity sequence usage and native counters", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "First answer"}}, %{reply: {:text, "Second answer"}}])
    config = config(mock, system_prompt: "Use prior answers")
    first = ReAct.run("First query", config, opts(jido))
    assert {:ok, saved, _} = Token.decode_state(first.final_token, config)
    assert saved.checkpoint.phase == :terminal
    second = QueryAppend.run(first.final_token, "Second query", config, opts(jido))
    assert second.result == "Second answer" and second.usage.total_tokens == 30

    assert Enum.all?(
             second.trace,
             &(&1.request_id == saved.request_id && &1.run_id == saved.run_id)
           )

    assert hd(second.trace).seq > saved.seq
    refute Enum.any?(second.trace, &(&1.kind == :request_started))
    assert Enum.count(second.trace, &(&1.kind == :llm_started)) == 1
    assert Enum.all?(second.trace, &(not Map.has_key?(&1.data, :react_checkpoint)))
    assert Enum.all?(second.trace, &(not Map.has_key?(&1.data[:meta] || %{}, :react_checkpoint)))
    [_, wire] = MockLLM.report(mock).requests
    assert users(wire) == ["First query", "Second query"]
    assert Enum.count(wire.body["messages"], &(&1["role"] == "system")) == 1

    assert Enum.any?(
             wire.body["messages"],
             &(&1["role"] == "assistant" && &1["content"] == "First answer")
           )

    assert {:ok, final, _} = Token.decode_state(second.final_token, config)
    assert final.iteration == 2
    assert final.checkpoint.runtime.model_calls == 2 and final.checkpoint.runtime.iterations == 2
    assert_script_done(mock)
  end

  test "append after tool completion keeps committed domain state without repeating effects", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "change", name: "change", arguments: %{count: 9}}]}},
        %{reply: {:text, "Nine"}},
        %{reply: {:text, "Still nine"}}
      ])

    config = config(mock, tools: [Change], request_transformer: Transform)
    options = opts(jido, %{count: 0})
    first = ReAct.run("Set count", config, options)
    assert first.result == "Nine"
    assert_receive {:standalone_count, 0}
    assert_receive {:standalone_count, 9}
    second = QueryAppend.run(first.final_token, "Read count", config, options)
    assert second.result == "Still nine" and second.usage.total_tokens == 45
    assert_receive {:standalone_count, 9}
    refute Enum.any?(second.trace, &(&1.kind == :tool_started))
    assert {:ok, final, _} = Token.decode_state(second.final_token, config)
    assert final.checkpoint.domain.count == 9 and final.checkpoint.effects == []

    assert Enum.count(
             List.last(MockLLM.report(mock).requests).body["messages"],
             &(&1["role"] == "tool")
           ) == 1

    assert_script_done(mock)
  end

  test "after-tools State has the next iteration and append retains its tool exchange", %{
    jido: jido
  } do
    {mock, _} = mock([tool(), %{reply: {:text, "After tools"}}])
    config = config(mock, tools: [Add])
    point = checkpoint(ReAct.stream("Sum", config, opts(jido)), :after_tools)
    assert {:ok, saved, _} = Token.decode_state(point.data.token, config)
    assert saved.iteration == 2 and saved.checkpoint.runtime.iterations == 1
    assert saved.checkpoint.runtime.model_calls == 1
    result = QueryAppend.run(point.data.token, "Explain it", config, opts(jido))
    assert result.result == "After tools" and result.usage.total_tokens == 30
    assert_receive {:standalone_add, _, 2, 3}
    refute_receive {:standalone_add, _, _, _}, 20
    [_, wire] = MockLLM.report(mock).requests
    assert users(wire) == ["Sum", "Explain it"]
    assert roles(wire) == ["user", "assistant", "tool", "user"]
    assert_script_done(mock)
  end

  test "append to pending tools finishes them before the new query reaches the model", %{
    jido: jido
  } do
    {mock, _} = mock([tool(), %{reply: {:text, "Explained"}}])
    config = config(mock, tools: [Add])
    point = checkpoint(ReAct.stream("Sum", config, opts(jido)), :after_llm)
    refute_receive {:standalone_add, _, _, _}, 20

    assert {:ok, next} =
             ReAct.continue(
               point.data.token,
               config,
               Keyword.put(opts(jido), :query, "Explain later")
             )

    after_tools = checkpoint(next.events, :after_tools)
    assert_receive {:standalone_add, _, 2, 3}
    assert {:ok, saved, _} = Token.decode_state(after_tools.data.token, config)
    assert saved.iteration == 2
    assert Enum.any?(saved.context.entries, &(&1.content == "Explain later"))
    assert {:ok, next} = ReAct.continue(after_tools.data.token, config, opts(jido))
    result = ReAct.collect_stream(next.events)
    assert result.result == "Explained"
    refute_receive {:standalone_add, _, _, _}, 20
    [_, wire] = MockLLM.report(mock).requests
    assert roles(wire) == ["user", "assistant", "tool", "user"]
    assert users(wire) == ["Sum", "Explain later"]
    assert_script_done(mock)
  end

  test "append at a final model checkpoint advances without publishing the old answer", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Saved answer"}}, %{reply: {:text, "New answer"}}])
    config = config(mock)
    point = checkpoint(ReAct.stream("Original", config, opts(jido)), :after_llm)
    result = QueryAppend.run(point.data.token, "New input", config, opts(jido))
    assert result.result == "New answer" and result.usage.total_tokens == 30
    assert Enum.count(result.trace, &(&1.kind == :request_completed)) == 1
    assert Enum.count(result.trace, &(&1.kind == :llm_started)) == 1
    assert_script_done(mock)
  end

  test "repair calls stay separate from reasoning iterations across terminal append", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:object, %{answer: 42}}},
        %{reply: {:object, %{answer: "Repaired"}}},
        %{reply: {:object, %{answer: "Next"}}}
      ])

    config =
      config(mock,
        max_iterations: 2,
        output: %{
          schema: Zoi.object(%{answer: Zoi.string()}),
          retries: 1,
          on_validation_error: :repair
        }
      )

    point =
      ReAct.stream("Repair", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_llm, 2)
      |> List.last()

    assert {:ok, saved, _} = Token.decode_state(point.data.token, config)
    assert saved.iteration == 1 and saved.checkpoint.runtime.model_calls == 2
    assert {:ok, next} = ReAct.continue(point.data.token, config, opts(jido))
    first = ReAct.collect_stream(next.events)
    assert first.result == %{answer: "Repaired"}
    result = QueryAppend.run(first.final_token, "Next input", config, opts(jido))
    assert result.result == %{answer: "Next"} and result.usage.total_tokens == 45
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.iteration == 2 and final.checkpoint.runtime.model_calls == 3
    assert final.checkpoint.runtime.iterations == 2
    assert_script_done(mock)
  end

  for query <- [nil, "", 42] do
    @query query
    test "ignored query option #{inspect(@query)} preserves a terminal result", %{jido: jido} do
      {mock, _} = mock([%{reply: {:text, "Saved"}}])
      config = config(mock)
      first = ReAct.run("Save", config, opts(jido))
      result = QueryAppend.run(first.final_token, @query, config, opts(jido))
      assert result.result == "Saved"
      assert Enum.map(result.trace, & &1.kind) == [:request_completed, :checkpoint]
      assert_script_done(mock)
    end
  end

  test "initial State append keeps rich content and sends both user entries once", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "File read"}}])
    model = put_in(MockLLM.model().extra.wire.protocol, "openai_responses")
    config = config(mock, model: model)

    query = [
      ReqLLM.Message.ContentPart.text("Read this"),
      ReqLLM.Message.ContentPart.file_id("file_append_123")
    ]

    state = State.new("Earlier input", nil)

    result =
      ReAct.stream_from_state(state, config, Keyword.put(opts(jido), :query, query))
      |> ReAct.collect_stream()

    assert result.result == "File read"
    [wire] = MockLLM.report(mock).requests
    [first, second] = Enum.filter(wire.body["input"], &(&1["role"] == "user"))
    assert Enum.any?(first["content"], &(&1["text"] == "Earlier input"))

    assert Enum.any?(
             second["content"],
             &(&1["type"] == "input_file" && &1["file_id"] == "file_append_123")
           )

    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.request_id == state.request_id and saved.run_id == state.run_id
    assert saved.iteration == 1
    assert_script_done(mock)
  end

  test "append cannot reset the reasoning budget after completion", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Only answer"}}])
    config = config(mock, max_iterations: 1)
    first = ReAct.run("One", config, opts(jido))
    result = QueryAppend.run(first.final_token, "Needs another", config, opts(jido))
    assert result.termination_reason == :max_iterations
    assert result.result == "Maximum iterations reached without a final answer."
    assert result.usage.total_tokens == 15
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.iteration == 2 and saved.checkpoint.runtime.model_calls == 1
    assert_script_done(mock)
  end

  test "append cannot reset the total tool budget", %{jido: jido} do
    {mock, _} = mock([tool(), %{reply: {:text, "First sum"}}, tool()])
    config = config(mock, tools: [Add])
    options = Keyword.put(opts(jido), :limits, %{timeout: 5_000, max_tool_calls: 1})
    first = ReAct.run("Sum", config, options)
    assert first.result == "First sum"
    assert_receive {:standalone_add, _, 2, 3}
    result = QueryAppend.run(first.final_token, "Sum again", config, options)
    assert result.termination_reason == :failed and result.usage.total_tokens == 45
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "new terminal tokens reject inconsistent State and native counters", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Saved"}}])
    config = config(mock)
    first = ReAct.run("Save", config, opts(jido))
    assert {:ok, saved, _} = Token.decode_state(first.final_token, config)
    assert saved.checkpoint.version == 2
    assert_raise ArgumentError, fn -> Token.issue(%{saved | iteration: 99}, config) end
    assert_script_done(mock)
  end

  test "query append retains the saved time bound when the caller supplies a larger limit", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "First"}}, %{reply: {:text, "Next"}}])
    config = config(mock)
    first = ReAct.run("First", config, opts(jido))
    assert {:ok, saved, _} = Token.decode_state(first.final_token, config)

    options =
      opts(jido)
      |> Keyword.put(:query, "Next")
      |> Keyword.put(:limits, %{timeout: 30_000, max_tool_calls: 32})

    assert {:ok, next} = ReAct.continue(first.final_token, config, options)
    point = checkpoint(next.events, :after_llm)
    assert {:ok, continued, _} = Token.decode_state(point.data.token, config)
    assert continued.checkpoint.remaining_ms <= saved.checkpoint.remaining_ms
    assert continued.checkpoint.remaining_ms < 5_000
    assert continued.checkpoint.runtime.model_calls == 2
    assert_script_done(mock)
  end

  defp tool, do: %{reply: {:tools, [%{id: "sum", name: "add", arguments: %{a: 2, b: 3}}]}}

  defp checkpoint(events, phase),
    do: events |> CheckpointResume.through_checkpoint(phase) |> List.last()

  defp users(wire),
    do: wire.body["messages"] |> Enum.filter(&(&1["role"] == "user")) |> Enum.map(& &1["content"])

  defp roles(wire),
    do: wire.body["messages"] |> Enum.reject(&(&1["role"] == "system")) |> Enum.map(& &1["role"])

  defp config(mock, extra \\ []),
    do:
      Config.new(
        Keyword.merge(
          [
            model: MockLLM.model(),
            tools: [],
            streaming: false,
            token_secret: "query-append-fixture",
            llm_opts: MockLLM.options(mock)
          ],
          extra
        )
      )

  defp opts(jido, state \\ %{}),
    do: [
      context: %{jido: jido, observer: self(), state: state},
      limits: %{timeout: 5_000, max_tool_calls: 32}
    ]
end
