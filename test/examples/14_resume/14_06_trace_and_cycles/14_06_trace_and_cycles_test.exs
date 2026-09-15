defmodule JidoAI.Examples.TraceAndCyclesTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, Token}
  alias JidoAI.Examples.CheckpointResume
  alias JidoAI.Examples.TraceAndCycles.{Agent, Check}

  setup do
    JidoAI.Examples.ToolEvents.attach_action(Check)
  end

  defp fingerprints(mock) do
    wire = List.last(MockLLM.report(mock).requests)

    for %{"role" => "tool", "content" => content} <- wire.body["messages"],
        do: Jason.decode!(content)["result"]["fingerprint"]
  end

  defp digest(payload),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(payload, [:deterministic])) |> Base.encode16(case: :lower)

  for redact? <- [true, false] do
    @redact? redact?
    test "tool start redaction #{@redact?} leaves the real tool input intact", %{jido: jido} do
      payload = %{
        "password" => "fixture-password",
        "nested" => %{"api_key" => "fixture-key", "name" => "Case"}
      }

      {mock, _} = mock([tool_round([call("secret", payload)]), %{reply: {:text, "Checked"}}])
      config = config(mock, redact_tool_args?: @redact?)
      result = ReAct.run("Check", config, opts(jido))
      assert result.result == "Checked"
      assert_receive {:example_action_started, "check"}
      assert fingerprints(mock) == [digest(payload)]
      event = Enum.find(result.trace, &(&1.kind == :tool_started))

      expected =
        if @redact?,
          do: %{
            "payload" => %{
              "password" => "[REDACTED]",
              "nested" => %{"api_key" => "[REDACTED]", "name" => "Case"}
            }
          },
          else: %{"payload" => payload}

      assert event.data.arguments == expected
      # This setting controls tool-start events. Execution history stays complete.
      response = Enum.find(result.trace, &(&1.kind == :llm_completed))
      assert hd(response.data.tool_calls).arguments == %{"payload" => payload}
      assert_script_done(mock)
    end
  end

  test "native Agent DSL applies the same tool event setting", %{jido: jido} do
    payload = %{"token" => "fixture-token"}
    {mock, context} = mock([tool_round([call("native", payload)]), %{reply: {:text, "Native"}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Jido.AI.Request.create_and_send(server, "Check",
               signal_type: "ai.ask",
               source: "/examples/trace",
               context: context,
               stream_to: self()
             )

    events = Jido.AI.Request.Stream.events(request) |> Enum.to_list()
    assert {:ok, "Native"} = Jido.AI.Request.await(request)

    assert Enum.find(events, &(&1.kind == :tool_started)).data.arguments == %{
             "payload" => payload
           }

    assert_receive {:example_action_started, "check"}
    assert fingerprints(mock) == [digest(payload)]
    assert_script_done(mock)
  end

  for capture? <- [true, false] do
    @capture? capture?
    test "delta capture #{@capture?} controls stream events and saved stream fields", %{
      jido: jido
    } do
      {mock, _} = mock([stream()])
      config = config(mock, streaming: true, capture_deltas?: @capture?)
      result = ReAct.run("Stream", config, opts(jido))
      assert result.result == "First second"
      assert Enum.any?(result.trace, &(&1.kind == :llm_delta)) == @capture?
      assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
      assert saved.streaming_text == if(@capture?, do: "First second", else: "")
      assert saved.streaming_thinking == if(@capture?, do: "Synthetic thought", else: "")

      checkpoint =
        Enum.find(result.trace, &(&1.kind == :checkpoint && &1.data.reason == :after_llm))

      assert {:ok, paused, _} = Token.decode_state(checkpoint.data.token, config)
      assert paused.streaming_text == saved.streaming_text
      assert paused.streaming_thinking == saved.streaming_thinking

      assert Enum.any?(
               saved.context.entries,
               &(&1.role == :assistant && &1.content == "First second")
             )

      assert_script_done(mock)
    end
  end

  test "a model checkpoint retains captured streams without provider replay", %{jido: jido} do
    {mock, _} = mock([stream()])
    config = config(mock, streaming: true)

    checkpoint =
      ReAct.stream("Stream", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_llm)
      |> List.last()

    assert {:ok, saved, _} = Token.decode_state(checkpoint.data.token, config)

    assert saved.streaming_text == "First second" and
             saved.streaming_thinking == "Synthetic thought"

    assert {:ok, continued} = ReAct.continue(checkpoint.data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)

    assert final.streaming_text == saved.streaming_text and
             final.streaming_thinking == saved.streaming_thinking

    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "the next model call resets captured text and thinking", %{jido: jido} do
    tools = [
      %{
        index: 0,
        id: "reset",
        type: "function",
        function: %{name: "check", arguments: Jason.encode!(%{payload: %{x: 1}})}
      }
    ]

    {mock, _} =
      mock([
        %{
          reply:
            {:stream, [%{reasoning_content: "Old thought"}, %{content: "Before"}, %{tool_calls: tools}], "tool_calls"}
        },
        %{reply: {:text, "After"}}
      ])

    config = config(mock, streaming: true)

    checkpoint =
      ReAct.stream("Reset", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_tools)
      |> List.last()

    assert {:ok, saved, _} = Token.decode_state(checkpoint.data.token, config)
    assert saved.streaming_text == "Before" and saved.streaming_thinking == "Old thought"
    assert {:ok, continued} = ReAct.continue(checkpoint.data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == "After"
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.streaming_text == "After" and final.streaming_thinking == ""
    assert_script_done(mock)
  end

  test "repeated arguments warn once after the real tools run despite changed IDs and order", %{
    jido: jido
  } do
    first = [call("a", %{n: 1}), call("b", %{n: 2})]
    second = [call("new-b", %{n: 2}), call("new-a", %{n: 1})]
    {mock, _} = mock([tool_round(first), tool_round(second), %{reply: {:text, "Done"}}])
    config = config(mock, tool_concurrency: 1)
    result = ReAct.run("Check twice", config, opts(jido))
    assert result.result == "Done"
    for _ <- 1..4, do: assert_receive({:example_action_started, "check"})
    assert fingerprints(mock) == Enum.map([1, 2, 2, 1], &digest(%{"n" => &1}))
    [_, second_wire, third_wire] = MockLLM.report(mock).requests
    assert warnings(second_wire) == []
    assert length(warnings(third_wire)) == 1
    assert Enum.count(result.trace, &(&1.kind == :tool_completed)) == 4
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert is_binary(saved.prev_tool_signature)
    assert Enum.count(saved.context.entries, &warning?/1) == 1
    assert_script_done(mock)
  end

  test "changed arguments with a long common prefix do not create a false cycle", %{jido: jido} do
    prefix = String.duplicate("a", 5_000)

    {mock, _} =
      mock([
        tool_round([call("a", %{text: prefix <> "first"})]),
        tool_round([call("b", %{text: prefix <> "second"})]),
        %{reply: {:text, "Changed"}}
      ])

    result = ReAct.run("Different suffix", config(mock), opts(jido))
    assert result.result == "Changed"
    assert Enum.all?(MockLLM.report(mock).requests, &(warnings(&1) == []))
    assert_script_done(mock)
  end

  test "completed tool checkpoints retain the signature and one warning across two resumes", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        tool_round([call("first", %{n: 1})]),
        tool_round([call("second", %{n: 1})]),
        %{reply: {:text, "Resumed"}}
      ])

    config = config(mock)

    first =
      ReAct.stream("Resume twice", config, opts(jido))
      |> CheckpointResume.through_checkpoint(:after_tools)
      |> List.last()

    assert {:ok, first_state, _} = Token.decode_state(first.data.token, config)
    assert is_binary(first_state.prev_tool_signature)
    assert {:ok, next} = ReAct.continue(first.data.token, config, opts(jido))
    second = next.events |> CheckpointResume.through_checkpoint(:after_tools) |> List.last()
    assert {:ok, second_state, _} = Token.decode_state(second.data.token, config)
    assert second_state.prev_tool_signature == first_state.prev_tool_signature
    assert Enum.count(second_state.context.entries, &warning?/1) == 1
    assert {:ok, next} = ReAct.continue(second.data.token, config, opts(jido))
    result = ReAct.collect_stream(next.events)
    assert result.result == "Resumed"
    assert length(warnings(List.last(MockLLM.report(mock).requests))) == 1
    assert_receive {:example_action_started, "check"}
    assert_receive {:example_action_started, "check"}
    assert fingerprints(mock) == [digest(%{"n" => 1}), digest(%{"n" => 1})]
    refute_received {:example_action_started, "check"}
    assert_script_done(mock)
  end

  test "different public tool names do not form a cycle even when they use the same Action", %{
    jido: jido
  } do
    other = %{call("second", %{n: 1}) | name: "other"}

    {mock, _} =
      mock([
        tool_round([call("first", %{n: 1})]),
        tool_round([other]),
        %{reply: {:text, "Two names"}}
      ])

    result =
      ReAct.run("Aliases", config(mock, tools: %{"check" => Check, "other" => Check}), opts(jido))

    assert result.result == "Two names"
    assert Enum.all?(MockLLM.report(mock).requests, &(warnings(&1) == []))
    assert_receive {:example_action_started, "check"}
    assert_receive {:example_action_started, "check"}
    assert fingerprints(mock) == [digest(%{"n" => 1}), digest(%{"n" => 1})]
    assert_script_done(mock)
  end

  test "a failed later model retains the completed tool signature", %{jido: jido} do
    {mock, _} =
      mock([
        tool_round([call("before-error", %{n: 1})]),
        %{reply: {:error, 400, "fixture failure"}}
      ])

    config = config(mock)
    result = ReAct.run("Fail later", config, opts(jido))
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.status == :failed
    assert is_binary(saved.prev_tool_signature)
    assert_script_done(mock)
  end

  defp call(id, payload), do: %{id: id, name: "check", arguments: %{payload: payload}}
  defp tool_round(calls), do: %{reply: {:tools, calls}}

  defp stream,
    do: %{
      reply:
        {:stream,
         [
           %{reasoning_content: "Synthetic "},
           %{reasoning_content: "thought"},
           %{content: "First "},
           %{content: "second"}
         ]}
    }

  defp warnings(wire), do: Enum.filter(wire.body["messages"], &warning?/1)

  defp warning?(entry) do
    role = Map.get(entry, :role, Map.get(entry, "role"))
    content = Map.get(entry, :content, Map.get(entry, "content"))

    role in [:user, "user"] and is_binary(content) and
      String.contains?(content, "identical parameters")
  end

  defp config(mock, extra \\ []) do
    Config.new(
      Keyword.merge(
        [
          model: MockLLM.model(),
          streaming: false,
          tools: [Check],
          token_secret: "trace-and-cycles-fixture",
          llm_opts: MockLLM.options(mock)
        ],
        extra
      )
    )
  end

  defp opts(jido),
    do: [context: %{jido: jido, observer: self()}, limits: %{timeout: 5_000, max_tool_calls: 32}]
end
