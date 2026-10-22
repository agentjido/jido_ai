defmodule JidoAI.Examples.StreamingTest do
  use ExUnit.Case, async: false

  import Mimic

  alias JidoAI.Examples.Streaming.Agent

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

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

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
