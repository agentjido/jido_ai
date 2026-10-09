defmodule Jido.AI.Integration.ReActNativeOutputTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Output
  alias Jido.AI.TestSupport.StreamResponseFactory

  defmodule NativeAgent do
    use Jido.AI.Agent,
      name: "native_output_test_agent",
      model: :capable,
      tools: [],
      output: [schema: Zoi.object(%{summary: Zoi.string()}), mode: :native]
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    :ok
  end

  test "a rejected final-tool batch does not poison the next request" do
    calls = :atomics.new(1, [])

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, messages, _opts ->
      chunks =
        case :atomics.add_get(calls, 1, 1) do
          1 ->
            [
              ReqLLM.StreamChunk.tool_call(Output.native_tool_name(), %{"summary" => "First"}, %{
                id: "rejected_1",
                index: 0
              }),
              ReqLLM.StreamChunk.tool_call(Output.native_tool_name(), %{"summary" => "Second"}, %{
                id: "rejected_2",
                index: 1
              })
            ]

          2 ->
            # Failed turns may be excluded by the agent's context policy. Any
            # retained calls must still have replies before the next request.
            for message <- messages, call <- message[:tool_calls] || [] do
              assert Enum.any?(messages, &(&1[:role] == :tool and &1[:tool_call_id] == call.id))
            end

            [ReqLLM.StreamChunk.tool_call(Output.native_tool_name(), %{"summary" => "Recovered"}, %{id: "recovered"})]
        end

      {:ok, StreamResponseFactory.build(chunks, %{finish_reason: :tool_calls}, model)}
    end)

    pid = start_supervised!({Jido.AgentServer, agent: NativeAgent})
    assert {:error, _reason} = NativeAgent.ask_sync(pid, "Ambiguous request", timeout: 5_000)
    assert {:ok, %{summary: "Recovered"}} = NativeAgent.ask_sync(pid, "Try again", timeout: 5_000)
    assert :atomics.get(calls, 1) == 2
  end

  test "native final answers reach ask_sync and preserve complete tool history across requests" do
    calls = :atomics.new(1, [])

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, messages, opts ->
      count = :atomics.add_get(calls, 1, 1)
      assert opts[:tool_choice] == :required
      assert [%ReqLLM.Tool{strict: true}] = opts[:tools]

      if count == 2 do
        assert Enum.any?(messages, fn message ->
                 message[:role] == :tool and message[:tool_call_id] == "native_request_1"
               end)
      end

      {:ok,
       StreamResponseFactory.build(
         [
           ReqLLM.StreamChunk.tool_call(
             Output.native_tool_name(),
             %{"summary" => "Request #{count}"},
             %{id: "native_request_#{count}"}
           )
         ],
         %{finish_reason: :tool_calls, usage: %{input_tokens: 1, output_tokens: 1}},
         model
       )}
    end)

    pid = start_supervised!({Jido.AgentServer, agent: NativeAgent})
    assert {:ok, %{summary: "Request 1"}} = NativeAgent.ask_sync(pid, "First request", timeout: 5_000)
    assert {:ok, %{summary: "Request 2"}} = NativeAgent.ask_sync(pid, "Second request", timeout: 5_000)
    assert :atomics.get(calls, 1) == 2
  end
end
