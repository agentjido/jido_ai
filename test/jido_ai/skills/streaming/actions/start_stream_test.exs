defmodule Jido.AI.Actions.Streaming.StartStreamTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Streaming.StartStream
  alias Jido.AI.TestSupport.FakeLLMClient

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert StartStream.schema().fields[:prompt].meta.required == true
      refute StartStream.schema().fields[:model].meta.required
      refute StartStream.schema().fields[:on_token].meta.required
      refute StartStream.schema().fields[:buffer].meta.required
    end

    test "has default values" do
      assert StartStream.schema().fields[:max_tokens].value == 1024
      assert StartStream.schema().fields[:temperature].value == 0.7
      assert StartStream.schema().fields[:buffer].value == false
      assert StartStream.schema().fields[:auto_process].value == true
    end
  end

  describe "run/2" do
    test "returns error when prompt is missing" do
      assert {:error, _} = StartStream.run(%{}, %{})
    end

    test "returns error when prompt is empty string" do
      assert {:error, _} = StartStream.run(%{prompt: ""}, %{})
    end

    test "generates stream_id with valid params" do
      params = %{
        prompt: "Test prompt",
        auto_process: false
      }

      assert {:ok, result} = StartStream.run(params, %{llm_client: FakeLLMClient})
      assert is_binary(result.stream_id)
      assert String.length(result.stream_id) > 0
      assert result.status == :pending
    end

    test "includes on_token callback in result" do
      params = %{
        prompt: "Tell me a story",
        on_token: fn token -> send(self(), {:token, token}) end,
        auto_process: false
      }

      assert {:ok, result} = StartStream.run(params, %{llm_client: FakeLLMClient})
      assert is_binary(result.stream_id)
    end

    test "respects buffer parameter" do
      params = %{
        prompt: "Write code",
        buffer: true,
        auto_process: false
      }

      assert {:ok, result} = StartStream.run(params, %{llm_client: FakeLLMClient})
      assert result.buffered == true
    end

    test "respects auto_process false" do
      params = %{
        prompt: "Generate text",
        auto_process: false
      }

      assert {:ok, result} = StartStream.run(params, %{llm_client: FakeLLMClient})
      assert is_binary(result.stream_id)
      assert result.status == :pending
    end

    test "returns structured error when auto_process true and supervisor is missing" do
      params = %{prompt: "Generate text", auto_process: true}
      assert {:error, :missing_task_supervisor} = StartStream.run(params, %{llm_client: FakeLLMClient})
    end

    test "auto-processes when task supervisor is provided" do
      {:ok, task_supervisor} = Task.Supervisor.start_link()

      params = %{
        prompt: "Generate text",
        auto_process: true,
        task_supervisor: task_supervisor
      }

      assert {:ok, result} = StartStream.run(params, %{llm_client: FakeLLMClient})
      assert result.status == :streaming
      assert is_binary(result.stream_id)
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        prompt: "Test goal",
        model: :fast
      }

      assert params[:model] == :fast
    end

    test "accepts string model spec" do
      params = %{
        prompt: "Test goal",
        model: "anthropic:claude-haiku-4-5"
      }

      assert params[:model] == "anthropic:claude-haiku-4-5"
    end
  end
end
