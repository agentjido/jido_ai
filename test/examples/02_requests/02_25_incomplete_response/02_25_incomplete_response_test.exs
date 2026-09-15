defmodule JidoAI.Examples.IncompleteResponseTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Context, Request, Session, Usage}
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.{Config, Token}
  alias JidoAI.Examples.IncompleteResponse.Agent
  alias ReqLLM.Message.ContentPart

  # ReqLLM's Chat decoder maps unrecognized strings, including incomplete and
  # cancelled, to :error. These inputs prove its canonical error reaches AI.
  # Exact Responses status preservation is a separate provider contract.
  for api <- [:agent, :standalone],
      {wire_reason, reason} <- [
        {"incomplete", :error},
        {"error", :error},
        {"cancelled", :error},
        {"length", :length},
        {"content_filter", :content_filter}
      ] do
    @tag history_case: "HIST-06/blank-terminal"
    test "#{api} rejects blank Chat #{wire_reason} as #{reason} without successful history", %{jido: jido} do
      reason = unquote(reason)
      usage = %{prompt_tokens: 5, completion_tokens: 0, total_tokens: 5}
      {mock, context} = mock([%{reply: {:stream, [], unquote(wire_reason), usage}}])
      result = execute(unquote(api), jido, mock, context)
      assert result.outcome == {:error, {:incomplete_response, reason}}
      assert result.status == :failed
      assert Enum.map(result.messages, & &1.role) == [:user]
      assert Jido.AI.Query.summarize(hd(result.messages).content) == "Hello"
      assert Usage.token_counts(result.usage) == %{input_tokens: 5, output_tokens: 0, total_tokens: 5}
      refute Enum.any?(result.events, &(&1.kind in [:llm_completed, :request_completed]))
      refute Enum.any?(result.events, &(&1.kind == :checkpoint and &1.data.reason == :after_llm))
      [failure] = Enum.filter(result.events, &(&1.kind == :request_failed))
      assert failure.data.error == {:incomplete_response, reason}
      assert failure.data.error_type == :llm_response
      assert failure.data.usage == result.usage
      assert length(MockLLM.report(mock).requests) == 1
      assert_script_done(mock)
    end
  end

  for api <- [:agent, :standalone], content <- [:text, :image] do
    @tag history_case: "HIST-06/accepted-partial"
    test "#{api} accepts partial #{content} and retains the length finish reason", %{jido: jido} do
      {deltas, expected} = partial(unquote(content))
      {mock, context} = mock([%{reply: {:stream, deltas, "length"}}])
      result = execute(unquote(api), jido, mock, context)
      assert result.outcome == {:ok, expected}
      assert result.status == :completed
      assert Enum.map(result.messages, & &1.role) == [:user, :assistant]
      [call] = Enum.filter(result.events, &(&1.kind == :llm_completed))
      assert call.data.finish_reason == :length
      [completed] = Enum.filter(result.events, &(&1.kind == :request_completed))
      assert completed.data.result == expected
      refute Enum.any?(result.events, &(&1.kind == :request_failed))
      assert result.usage.total_tokens == 15
      assert_script_done(mock)
    end
  end

  for api <- [:agent, :standalone] do
    @tag history_case: "HIST-06/finish-reason-inputs"
    test "#{api} keeps blank successful stop distinct from a failed finish reason", %{jido: jido} do
      {mock, context} = mock([%{reply: {:stream, [], "stop"}}])
      result = execute(unquote(api), jido, mock, context)
      assert result.outcome == {:ok, ""}
      assert result.status == :completed
      [call] = Enum.filter(result.events, &(&1.kind == :llm_completed))
      assert call.data.finish_reason == :stop
      assert_script_done(mock)
    end
  end

  defp partial(:text), do: {[%{content: "Partial answer"}], "Partial answer"}

  defp partial(:image) do
    delta = %{images: [%{type: "image_url", image_url: %{url: "data:image/png;base64,AQID"}}]}
    {[delta], [ContentPart.image(<<1, 2, 3>>, "image/png")]}
  end

  defp execute(:agent, jido, _mock, context) do
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Request.create_and_send(server, "Hello",
               signal_type: "ai.ask",
               source: "/examples/incomplete",
               context: context,
               stream_to: self()
             )

    outcome = Request.await(request)
    events = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
    agent = Server.agent(server)
    record = agent.state.requests[request.id]
    if record.status == :failed, do: assert(agent.state.reply == "untouched")
    assert {:ok, %{live: nil}} = Session.snapshot(server)
    assert :ok = Jido.Action.validate_static_data(agent.state)
    %{outcome: outcome, status: record.status, events: events, usage: record.meta.usage, messages: conversation(agent)}
  end

  defp execute(:standalone, jido, mock, _context) do
    config =
      Config.new(%{
        model: MockLLM.model(),
        tools: [],
        llm_opts: MockLLM.options(mock),
        token_secret: "incomplete-example"
      })

    result = ReAct.run("Hello", config, context: %{jido: jido})
    assert {:ok, saved, _} = Token.decode_state(result.final_token, config)
    assert :ok = Jido.Action.validate_static_data(saved.checkpoint)
    terminal = Enum.find(result.trace, &(&1.kind == :checkpoint and &1.data.reason == :terminal))
    assert terminal.data.token == result.final_token
    assert result.usage == saved.usage
    outcome = if saved.status == :completed, do: {:ok, result.result}, else: {:error, saved.error}

    %{
      outcome: outcome,
      status: saved.status,
      events: result.trace,
      usage: saved.usage,
      messages: Context.to_messages(saved.context)
    }
  end
end
