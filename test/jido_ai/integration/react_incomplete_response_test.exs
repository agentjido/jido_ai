defmodule Jido.AI.Integration.ReActIncompleteResponseTest do
  @moduledoc """
  Regression tests for blank terminal responses that providers report as
  failures or truncations.
  """
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.TestSupport.StreamResponseFactory

  defmodule BasicAgent do
    use Jido.AI.Agent,
      name: "incomplete_response_test_agent",
      model: "test:model",
      tools: []
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    :ok
  end

  defp start_basic_agent do
    {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp stub_blank_stream_response(finish_reason) do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       StreamResponseFactory.build(
         [],
         %{finish_reason: finish_reason, usage: %{input_tokens: 5, output_tokens: 0}},
         model
       )}
    end)
  end

  describe "blank terminal streaming response" do
    test "returns {:error, {:incomplete_response, :incomplete}} instead of {:ok, \"\"}" do
      stub_blank_stream_response(:incomplete)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :incomplete}}} = result
    end

    test "does not return {:ok, \"\"} for incomplete response" do
      stub_blank_stream_response(:incomplete)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      refute result == {:ok, ""}
    end

    test "returns {:error, {:incomplete_response, :error}} for error finish_reason with blank text" do
      stub_blank_stream_response(:error)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :error}}} = result
    end

    test "returns {:error, {:incomplete_response, :cancelled}} for cancelled finish_reason with blank text" do
      stub_blank_stream_response(:cancelled)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :cancelled}}} = result
    end

    test "returns {:error, {:incomplete_response, :length}} for truncated blank responses" do
      stub_blank_stream_response(:length)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :length}}} = result
    end

    test "returns {:error, {:incomplete_response, :content_filter}} for filtered blank responses" do
      stub_blank_stream_response(:content_filter)

      pid = start_basic_agent()
      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :content_filter}}} = result
    end

    test "successful response with :stop still returns {:ok, text}" do
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        {:ok,
         StreamResponseFactory.build(
           [ReqLLM.StreamChunk.text("Hello, World!")],
           %{finish_reason: :stop, usage: %{input_tokens: 5, output_tokens: 10}},
           model
         )}
      end)

      pid = start_basic_agent()

      assert {:ok, "Hello, World!"} = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)
    end

    test "incomplete finish_reason with actual text content is still accepted as final answer" do
      # Edge case: if the model managed to emit text before getting cut off,
      # we should still accept it rather than silently discarding a partial response.
      # The validation only rejects blank text + failure finish_reason.
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        {:ok,
         StreamResponseFactory.build(
           [ReqLLM.StreamChunk.text("Partial response before cutoff")],
           %{finish_reason: :incomplete, usage: %{input_tokens: 5, output_tokens: 5}},
           model
         )}
      end)

      pid = start_basic_agent()

      assert {:ok, "Partial response before cutoff"} = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)
    end
  end
end
