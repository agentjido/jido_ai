defmodule JidoAI.Examples.StreamUsageTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session, Usage}
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.{Config, Token}
  alias JidoAI.Examples.StreamUsage.{Agent, QuietAgent, Echo}

  for api <- [:agent, :standalone], capture? <- [true, false] do
    @tag history_case: "HIST-13/usage-source-precedence"
    test "#{api} retains numeric-string provider usage with delta capture #{capture?}", %{jido: jido} do
      usage = %{prompt_tokens: "3", completion_tokens: "1", total_tokens: "4"}
      {mock, context} = mock([%{reply: {:stream, [%{content: "Done"}], "stop", usage}}])
      {events, stored} = execute(unquote(api), unquote(capture?), jido, mock, context)
      assert stored.total_tokens == 4
      [call] = Enum.filter(events, &(&1.kind == :llm_completed))
      assert Usage.token_counts(call.data.usage) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
      assert Enum.any?(events, &(&1.kind == :llm_delta)) == unquote(capture?)
      assert length(MockLLM.report(mock).requests) == 1
      assert_script_done(mock)
    end
  end

  for api <- [:agent, :standalone] do
    @tag history_case: "HIST-13/usage-source-precedence"
    test "#{api} preserves an explicit provider zero", %{jido: jido} do
      usage = %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
      {mock, context} = mock([%{reply: {:stream, [%{content: "Done"}], "stop", usage}}])
      {events, stored} = execute(unquote(api), true, jido, mock, context)
      assert stored.total_tokens == 0
      [call] = Enum.filter(events, &(&1.kind == :llm_completed))
      assert Usage.token_counts(call.data.usage) == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
      assert_script_done(mock)
    end

    @tag history_case: "HIST-13/stream-cumulative-usage"
    test "#{api} uses one cumulative count per tool round and adds separate calls", %{jido: jido} do
      usage = %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}

      call = %{
        tool_calls: [%{index: 0, id: "one", type: "function", function: %{name: "usage_echo", arguments: ~s({"n":7})}}]
      }

      {mock, context} =
        mock([
          %{
            reply:
              {:stream,
               [
                 call,
                 {:usage, usage},
                 {:usage, usage},
                 {:usage, %{prompt_tokens: 2, completion_tokens: 1, total_tokens: 3}}
               ], "tool_calls", usage}
          },
          %{reply: {:stream, [%{content: "Done"}], "stop", %{prompt_tokens: 2, completion_tokens: 1, total_tokens: 3}}}
        ])

      {events, stored} = execute(unquote(api), false, jido, mock, context)
      assert stored.total_tokens == 8

      assert Enum.map(
               Enum.filter(events, &(&1.kind == :llm_completed)),
               &Usage.token_counts(&1.data.usage).total_tokens
             ) == [5, 3]

      assert_receive {:usage_tool, 7}
      [_, last] = MockLLM.report(mock).requests
      [tool] = Enum.filter(last.body["messages"], &(&1["role"] == "tool"))
      assert tool["tool_call_id"] == "one"
      assert Jason.decode!(tool["content"]) == %{"ok" => true, "result" => %{"n" => 7}}
      assert_script_done(mock)
    end
  end

  defp execute(:agent, capture?, jido, _mock, context) do
    module = if capture?, do: Agent, else: QuietAgent
    server = start_agent(jido, module.new!())

    assert {:ok, request} =
             Request.create_and_send(server, "Work",
               signal_type: "ai.ask",
               source: "/examples/stream_usage",
               context: context,
               stream_to: self()
             )

    assert {:ok, "Done"} = Request.await(request)
    events = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
    record = Server.agent(server).state.requests[request.id]
    assert record.status == :completed
    assert {:ok, %{live: nil}} = Session.snapshot(server)
    assert List.last(events).data.usage == record.meta.usage
    {events, record.meta.usage}
  end

  defp execute(:standalone, capture?, jido, mock, _context) do
    config =
      Config.new(%{
        model: MockLLM.model(),
        tools: [Echo],
        llm_opts: MockLLM.options(mock),
        capture_deltas?: capture?,
        token_secret: "usage-test-secret"
      })

    result = ReAct.run("Work", config, context: %{jido: jido, observer: self()})
    assert result.result == "Done"
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert saved.status == :completed
    assert saved.usage == result.usage
    {result.trace, result.usage}
  end
end
