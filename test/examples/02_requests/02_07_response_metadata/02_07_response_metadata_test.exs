defmodule JidoAI.Examples.ResponseMetadataTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.ResponseMetadata.{Agent, StreamAgent}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  defp details(signature),
    do: [%{signature: signature, signature_encrypted: true, format: "openai", index: 0}]

  defp reply(message, finish \\ "stop") do
    {:raw,
     %{
       id: "fixture-response",
       object: "chat.completion",
       model: "gpt-4o-mini",
       choices: [
         %{index: 0, message: Map.put(message, :role, "assistant"), finish_reason: finish}
       ],
       usage: %{
         prompt_tokens: 10,
         completion_tokens: 5,
         total_tokens: 15,
         completion_tokens_details: %{reasoning_tokens: 3}
       }
     }}
  end

  defp tool_reply do
    reply(
      %{
        content: nil,
        reasoning_content: "Synthetic lookup thought",
        reasoning_details: details("fixture-lookup"),
        tool_calls: [
          %{
            id: "lookup",
            type: "function",
            function: %{name: "scope_echo", arguments: ~s({"value":7})}
          }
        ]
      },
      "tool_calls"
    )
  end

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  for module <- [Agent, StreamAgent], with_tool <- [false, true] do
    @tag history_case: "HIST-14/completed-metadata"
    test "#{inspect(module)} retains final_answer termination with tool round #{with_tool}", %{jido: jido} do
      script = [%{reply: {:text, "Done"}}]

      script =
        if unquote(with_tool),
          do: [%{reply: {:tools, [%{id: "one", name: "scope_echo", arguments: %{value: 7}}]}} | script],
          else: script

      {mock, context} = mock(script)
      module = unquote(module)
      server = start_agent(jido, module.new!())
      assert {:ok, request} = module.ask(server, "Work", context: context, stream_to: self())
      assert {:ok, "Done"} = module.await(request)
      rec = record(server, request)
      assert rec.status == :completed and rec.meta.termination_reason == :final_answer
      assert rec.meta.model_calls == unquote(if with_tool, do: 2, else: 1)
      assert rec.meta.usage.total_tokens == unquote(if with_tool, do: 30, else: 15)
      terminal = List.last(events(request))
      assert terminal.kind == :request_completed
      assert terminal.data.termination_reason == :final_answer
      assert terminal.data.meta == rec.meta
      assert {:ok, view} = Session.snapshot(server)
      assert view.details.termination_reason == :final_answer
      assert view.details.phase == :request_completed and view.live == nil
      assert_script_done(mock)
    end
  end

  @tag history_case: "HIST-14/completed-metadata"
  test "decoded response metadata stays in its request and keeps public result tuples", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{
          reply:
            reply(%{
              content: "First",
              reasoning_content: "Synthetic final thought",
              reasoning_details: details("fixture-final")
            })
        },
        %{reply: {:text, "Second"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "First", context: context, stream_to: self())
    assert {:ok, "First"} = Agent.await(request)
    meta = record(server, request).meta
    assert meta.usage.total_tokens == 15
    assert meta.usage.reasoning_tokens == 3
    assert meta.last_thinking == "Synthetic final thought"

    assert [%ReqLLM.Message.ReasoningDetails{signature: "fixture-final", encrypted?: true}] =
             meta.reasoning_details

    assert [%{call_id: call_id, iteration: 1, thinking: "Synthetic final thought"}] =
             meta.thinking_trace

    responses = events(request)
    response = Enum.find(responses, &(&1.kind == :llm_completed))
    assert response.llm_call_id == call_id
    assert response.data.call_id == call_id
    assert response.data.response_id == "fixture-response"
    assert response.data.turn_type == :final_answer
    assert response.data.text == "First"
    assert response.data.thinking_content == meta.last_thinking
    assert response.data.reasoning_details == meta.reasoning_details
    assert Enum.any?(response.data.content_parts, &(&1.type == :thinking))
    assert List.last(responses).data.meta == meta
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)

    assert {:ok, "Second"} = Agent.ask_sync(server, "Second", context: context)
    state = Server.agent(server).state
    second = state.requests[state.last_request_id]
    refute second.id == request.id
    refute Map.has_key?(second.meta, :last_thinking)
    refute Map.has_key?(second.meta, :thinking_trace)
    refute Map.has_key?(second.meta, :reasoning_details)
    assert state.requests[request.id].meta == meta
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/completed-metadata"
  test "tool rounds retain separate thinking entries and the final response details", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: tool_reply()},
        %{
          reply:
            reply(%{
              content: "Seven",
              reasoning_content: "Synthetic final thought",
              reasoning_details: details("fixture-final")
            })
        }
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Lookup", context: context, stream_to: self())
    assert {:ok, "Seven"} = Agent.await(request)
    meta = record(server, request).meta
    responses = Enum.filter(events(request), &(&1.kind == :llm_completed))
    assert Enum.map(responses, & &1.data.turn_type) == [:tool_calls, :final_answer]
    assert Enum.map(meta.thinking_trace, & &1.iteration) == [1, 2]

    assert Enum.map(meta.thinking_trace, & &1.thinking) == [
             "Synthetic lookup thought",
             "Synthetic final thought"
           ]

    assert Enum.map(meta.thinking_trace, & &1.call_id) == Enum.map(responses, & &1.llm_call_id)
    assert length(Enum.uniq_by(responses, & &1.llm_call_id)) == 2
    assert [%{signature: "fixture-final"}] = meta.reasoning_details
    assert meta.usage.total_tokens == 30
    assert meta.usage.reasoning_tokens == 6

    assert [%{id: "lookup", name: "scope_echo", arguments: %{"value" => 7}}] =
             hd(responses).data.tool_calls

    assert_script_done(mock)
  end

  test "a final response without thinking retains earlier trace and reasoning details", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: tool_reply()}, %{reply: {:text, "Seven"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Lookup", context: context)
    assert {:ok, "Seven"} = Agent.await(request)
    meta = record(server, request).meta
    assert [%{thinking: "Synthetic lookup thought"}] = meta.thinking_trace
    assert [%{signature: "fixture-lookup"}] = meta.reasoning_details
    refute Map.has_key?(meta, :last_thinking)
    assert_script_done(mock)
  end

  test "typed output repair retains metadata for each actual model call", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: reply(%{content: "Invalid JSON", reasoning_content: "Synthetic draft thought"})},
        %{
          reply:
            reply(%{
              content: ~s({"answer":"Repaired"}),
              reasoning_content: "Synthetic repair thought",
              reasoning_details: details("fixture-repair")
            })
        }
      ])

    server = start_agent(jido, Agent.new!())
    output = [schema: Zoi.object(%{answer: Zoi.string()}), retries: 1]

    assert {:ok, request} =
             Agent.ask(server, "Repair", context: context, output: output, stream_to: self())

    assert {:ok, %{answer: "Repaired"}} = Agent.await(request)
    meta = record(server, request).meta

    assert Enum.map(meta.thinking_trace, & &1.thinking) == [
             "Synthetic draft thought",
             "Synthetic repair thought"
           ]

    assert Enum.map(meta.thinking_trace, & &1.iteration) == [1, 2]
    assert meta.last_thinking == "Synthetic repair thought"
    assert [%{signature: "fixture-repair"}] = meta.reasoning_details
    assert meta.output.status == :repaired
    assert meta.output.attempt == 1
    assert meta.model_calls == 2
    assert meta.usage.total_tokens == 30
    assert List.last(events(request)).data.meta == meta
    assert_script_done(mock)
  end

  test "stream decoding keeps synthetic thinking and reasoning details separate from text", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{
          reply:
            {:stream,
             [
               %{reasoning_content: "Synthetic "},
               %{reasoning_content: "stream thought"},
               %{reasoning_details: details("fixture-stream")},
               %{content: "Answer"}
             ]}
        }
      ])

    server = start_agent(jido, StreamAgent.new!())
    assert {:ok, request} = StreamAgent.ask(server, "Stream", context: context, stream_to: self())
    assert {:ok, "Answer"} = StreamAgent.await(request)
    meta = record(server, request).meta
    assert meta.last_thinking == "Synthetic stream thought"
    assert [%{signature: "fixture-stream"}] = meta.reasoning_details
    responses = events(request)
    assert Enum.any?(responses, &(&1.kind == :llm_delta && &1.data[:chunk_type] == :thinking))

    assert Enum.find(responses, &(&1.kind == :llm_completed)).data.thinking_content ==
             meta.last_thinking

    assert List.last(responses).data.meta == meta
    assert_script_done(mock)
  end

  for {name, fields} <- [
        {"empty", %{reasoning_content: "", reasoning_details: []}},
        {"invalid", %{reasoning_content: 42, reasoning_details: "invalid"}}
      ] do
    test "#{name} optional provider metadata is omitted from the completed request", %{jido: jido} do
      {mock, context} =
        mock([%{reply: reply(Map.put(unquote(Macro.escape(fields)), :content, "Answer"))}])

      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = Agent.ask(server, "Answer", context: context)
      assert {:ok, "Answer"} = Agent.await(request)
      meta = record(server, request).meta
      refute Map.has_key?(meta, :last_thinking)
      refute Map.has_key?(meta, :thinking_trace)
      refute Map.has_key?(meta, :reasoning_details)
      assert_script_done(mock)
    end
  end

  test "a later provider failure retains metadata from completed model calls", %{jido: jido} do
    {mock, context} = mock([%{reply: tool_reply()}, %{reply: {:error, 503, "Fixture failure"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Lookup", context: context, stream_to: self())
    assert {:error, _} = Agent.await(request)
    meta = record(server, request).meta
    assert [%{thinking: "Synthetic lookup thought"}] = meta.thinking_trace
    assert [%{signature: "fixture-lookup"}] = meta.reasoning_details
    assert meta.usage.total_tokens == 15
    responses = events(request)
    assert List.last(responses).kind == :request_failed
    assert List.last(responses).data.meta == meta
    assert_script_done(mock)
  end

  test "cancellation retains completed call metadata without taking data from a later request", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: tool_reply()},
        %{reply: {:wait, :answer, {:text, "Late"}}},
        %{reply: {:text, "Next"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Lookup", context: context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :answer, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Agent.await(request)
    meta = record(server, request).meta
    assert [%{thinking: "Synthetic lookup thought"}] = meta.thinking_trace
    assert [%{signature: "fixture-lookup"}] = meta.reasoning_details
    assert meta.usage.total_tokens == 15
    assert List.last(events(request)).data.meta == meta
    assert MockLLM.release(mock, :answer) in [:ok, {:error, :not_waiting}]
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:ok, "Next"} = Agent.ask_sync(server, "Next", context: context)
    assert record(server, request).meta == meta
    state = Server.agent(server).state
    refute Map.has_key?(state.requests[state.last_request_id].meta, :reasoning_details)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/metadata-precedence"
  test "snapshot details and explicit overrides keep their order and unrelated metadata", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Answer"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Answer", context: context)
    assert {:ok, "Answer"} = Agent.await(request)
    agent = Server.agent(server)
    agent = put_in(agent.state.requests[request.id].meta[:application], %{ticket: "case-1"})

    snapshot = %{
      result: %{
        answer: "Imported",
        usage: %{total_tokens: 99},
        reasoning_details: [%{signature: "result"}],
        thinking_content: "Result thought"
      },
      details: %{
        "usage" => %{total_tokens: 10},
        "reasoning_details" => [%{signature: "details"}],
        "thinking_trace" => [%{thinking: "Trace"}],
        "streaming_thinking" => "Detail thought",
        "last_thinking" => "Earlier thought",
        "output" => %{status: :validated}
      }
    }

    derived = Request.complete_request_from_snapshot(agent, request.id, snapshot)
    meta = derived.state.requests[request.id].meta
    assert meta.usage == %{total_tokens: 10}
    assert meta.reasoning_details == [%{signature: "details"}]
    assert meta.last_thinking == "Detail thought"
    assert meta.thinking_trace == [%{thinking: "Trace"}]
    assert meta.output == %{status: :validated}
    assert meta.application == %{ticket: "case-1"}
    override = %{usage: %{}, reasoning_details: [], last_thinking: "Override"}
    explicit = Request.complete_request_from_snapshot(agent, request.id, snapshot, meta: override)
    assert Map.take(explicit.state.requests[request.id].meta, Map.keys(override)) == override
    assert explicit.state.requests[request.id].result == snapshot.result
    assert explicit.state.requests[request.id].meta.application == %{ticket: "case-1"}
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/metadata-precedence"
  test "absent and empty snapshot fields use the defined result and conversation fallbacks" do
    result = %{
      "usage" => %{total_tokens: 9},
      "reasoning_details" => [%{signature: "result"}],
      "thinking_content" => "Result thought"
    }

    conversation = [
      %{role: :assistant, reasoning_details: [%{signature: "earlier"}]},
      %{"role" => "assistant", "reasoning_details" => [%{signature: "latest"}]},
      %{role: :assistant, reasoning_details: []},
      %{role: :tool, reasoning_details: [%{signature: "ignored"}]}
    ]

    missing =
      Jido.AI.Request.Metadata.from_snapshot(%{
        result: result,
        details: %{conversation: conversation}
      })

    assert missing == %{
             usage: %{total_tokens: 9},
             reasoning_details: [%{signature: "result"}],
             last_thinking: "Result thought"
           }

    empty =
      Jido.AI.Request.Metadata.from_snapshot(%{
        result: result,
        details: %{
          usage: %{},
          reasoning_details: [],
          streaming_thinking: "",
          last_thinking: "Ignored",
          conversation: conversation
        }
      })

    refute Map.has_key?(empty, :usage)
    assert empty.reasoning_details == [%{signature: "latest"}]
    assert empty.last_thinking == "Result thought"
    assert Jido.AI.Request.Metadata.from_snapshot(%{result: result, details: nil}) == %{}
    assert Jido.AI.Request.Metadata.from_snapshot(%{result: result}) == %{}

    assert Jido.AI.Request.Metadata.from_snapshot(%{
             result: "Answer",
             details: %{
               usage: [],
               thinking_trace: 42,
               streaming_thinking: false,
               output: "invalid"
             }
           }) == %{}
  end
end
