defmodule JidoAI.Examples.StreamingTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias JidoAI.Examples.Streaming.Agent

  @moduletag :example

  test "the Agent returns a stream that can be read and closed" do
    test_process = self()

    expect(ReqLLM, :stream_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert options[:receive_timeout] in 1..60_000
      assert Keyword.keys(options) == [:receive_timeout]

      {:ok, metadata_handle} =
        ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> %{finish_reason: :stop} end)

      {:ok,
       %ReqLLM.StreamResponse{
         stream: [ReqLLM.StreamChunk.text("Ready"), ReqLLM.StreamChunk.text(" now")],
         metadata_handle: metadata_handle,
         cancel: fn ->
           send(test_process, :stream_cancelled)
           :ok
         end,
         model: model,
         context: context
       }}
    end)

    assert {:ok, stream_response} = Agent.stream("Are you ready?")
    assert Enum.to_list(ReqLLM.StreamResponse.tokens(stream_response)) == ["Ready", " now"]
    assert :ok = ReqLLM.StreamResponse.close(stream_response)
    assert_receive :stream_cancelled
  end
end
