defmodule Jido.AI.Integration.ReActIncompleteResponseTest do
  @moduledoc """
  Regression tests for the bug where an incomplete or empty LLM response
  (finish_reason: :incomplete with blank text) was silently accepted as a
  successful final answer, causing ask_sync/3 to return {:ok, ""} instead of
  {:error, reason}.
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

  describe "incomplete streaming response" do
    test "returns {:error, {:incomplete_response, :incomplete}} instead of {:ok, \"\"}" do
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        # Simulate provider failure: stream closes with no content and finish_reason: :incomplete
        {:ok,
         StreamResponseFactory.build(
           [],
           %{finish_reason: :incomplete, usage: %{input_tokens: 5, output_tokens: 0}},
           model
         )}
      end)

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :incomplete}}} = result
    end

    test "does not return {:ok, \"\"} for incomplete response" do
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        {:ok,
         StreamResponseFactory.build(
           [],
           %{finish_reason: :incomplete, usage: %{input_tokens: 5, output_tokens: 0}},
           model
         )}
      end)

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      refute result == {:ok, ""}
    end

    test "returns {:error, {:incomplete_response, :error}} for error finish_reason with blank text" do
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        {:ok,
         StreamResponseFactory.build(
           [],
           %{finish_reason: :error, usage: %{input_tokens: 5, output_tokens: 0}},
           model
         )}
      end)

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :error}}} = result
    end

    test "returns {:error, {:incomplete_response, :cancelled}} for cancelled finish_reason with blank text" do
      Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
        {:ok,
         StreamResponseFactory.build(
           [],
           %{finish_reason: :cancelled, usage: %{input_tokens: 5, output_tokens: 0}},
           model
         )}
      end)

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      result = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)

      assert {:error, {:failed, :error, {:incomplete_response, :cancelled}}} = result
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

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

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

      {:ok, pid} = Jido.AgentServer.start_link(agent: BasicAgent)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      assert {:ok, "Partial response before cutoff"} = BasicAgent.ask_sync(pid, "Hello!", timeout: 5_000)
    end
  end
end
