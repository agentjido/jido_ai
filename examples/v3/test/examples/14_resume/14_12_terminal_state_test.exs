defmodule JidoAI.Examples.TerminalStateTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session, Usage}
  alias Jido.AI.Reasoning.ReAct
  alias JidoAI.Examples.TerminalState

  defp submit(server, context, query) do
    Request.create_and_send(server, query,
      signal_type: "ai.ask",
      source: "/examples/terminal-state",
      context: context,
      stream_to: self()
    )
  end

  defp reply(stream?, kind, usage) do
    call = %{id: "once", type: "function", function: %{name: "terminal_echo", arguments: Jason.encode!(%{value: 5})}}

    {message, delta, finish} =
      case kind do
        :tool ->
          {%{role: "assistant", content: nil, tool_calls: [call]}, %{tool_calls: [Map.put(call, :index, 0)]},
           "tool_calls"}

        text ->
          {%{role: "assistant", content: text}, %{content: text}, "stop"}
      end

    if stream? do
      {:stream, [delta], finish, usage}
    else
      {:raw,
       %{
         id: "terminal-model",
         object: "chat.completion",
         model: "gpt-4o-mini",
         choices: [%{index: 0, message: message, finish_reason: finish}],
         usage: usage
       }}
    end
  end

  defp failure(:complete), do: nil
  defp failure(:map), do: %{type: :stream_error, status: 503, message: "Too many connections"}
  defp failure(:tuple), do: {:incomplete_response, :incomplete}

  defp terminal(nil), do: {{:ok, "Done"}, :completed, "Done", :request_completed, "Done"}
  defp terminal(raw), do: {{:error, raw}, :failed, nil, :request_failed, raw}

  for {module, stream?} <- [{TerminalState.Buffered, false}, {TerminalState.Streamed, true}],
      outcome <- [:complete, :map, :tuple] do
    test "#{module} keeps #{outcome} terminal state, usage and tool history after native restore", %{jido: jido} do
      usage = %{prompt_tokens: 3, completion_tokens: 1, total_tokens: 4}
      next_usage = %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2}

      {mock, context} =
        mock([
          %{reply: reply(unquote(stream?), :tool, usage)},
          %{reply: reply(unquote(stream?), "Done", %{})},
          %{reply: reply(unquote(stream?), "Next", next_usage)}
        ])

      raw = failure(unquote(outcome))
      {expected, status, result, phase, collected_result} = terminal(raw)
      server = start_agent(jido, unquote(module).new!())
      assert {:ok, request} = submit(server, Map.put(context, :failure, raw), "Use the tool")
      assert Request.await(request) == expected
      assert_receive {:terminal_tool, 5}, 2_000
      refute_receive {:terminal_tool, _}, 30
      assert {:ok, view} = Session.snapshot(server)
      assert view.live == nil and view.details.active_request_id == nil
      assert view.request.status == status
      assert view.request.error == raw
      assert view.request.result == result
      assert Usage.token_counts(view.details.usage) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
      assert view.details.model_calls == 2
      assert [%{id: "once", result: {:ok, %{value: 5}, []}}] = view.details.tool_results

      streamed = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
      terminal = Enum.filter(streamed, &(&1.kind in [:request_completed, :request_failed]))
      assert length(terminal) == 1
      assert List.last(terminal).data[:error] == raw

      absent =
        Enum.map(streamed, fn event ->
          if event.kind in [:request_completed, :request_failed],
            do: %{event | data: Map.put(event.data, :usage, %{})},
            else: event
        end)

      collected = ReAct.collect_stream(absent)
      assert collected.result == collected_result
      assert Usage.token_counts(collected.usage) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}

      assert {:ok, checkpoint} = Jido.Agent.checkpoint(view.agent)
      assert checkpoint.kind == :agent and checkpoint.state.requests[request.id] == view.request
      assert :ok = Jido.Action.validate_static_data(checkpoint)
      copy = checkpoint |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
      assert :ok = Server.stop(server, :normal)
      assert {:ok, agent} = Jido.Agent.restore(unquote(module), copy)
      restored = start_agent(jido, agent)
      assert {:ok, saved} = Session.snapshot(restored, request_id: request.id)
      assert saved.request == view.request and saved.details.trace == view.details.trace
      assert saved.live == nil and saved.details.active_request_id == nil
      assert saved.details.phase == phase
      assert length(MockLLM.report(mock).requests) == 2
      refute_receive {:terminal_tool, _}, 30

      assert {:ok, next} = submit(restored, context, "Continue")
      assert {:ok, "Next"} = Request.await(next)
      assert {:ok, old} = Session.snapshot(restored, request_id: request.id)
      assert old.request == view.request
      assert {:ok, fresh} = Session.snapshot(restored, request_id: next.id)
      assert Usage.token_counts(fresh.details.usage) == %{input_tokens: 1, output_tokens: 1, total_tokens: 2}
      assert fresh.details.tool_results == []
      wires = MockLLM.report(mock).requests
      assert Enum.all?(wires, &(&1.body["stream"] == unquote(stream?)))
      assert Enum.count(List.last(wires).body["messages"], &(&1["role"] == "tool")) == 1
      refute_receive {:terminal_tool, _}, 30
      assert_script_done(mock)
    end
  end
end
