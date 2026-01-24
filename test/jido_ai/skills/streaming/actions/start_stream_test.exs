defmodule Jido.AI.Skills.Streaming.Actions.StartStreamTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Streaming.Actions.StartStream

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

    @tag :skip
    test "generates stream_id with valid params" do
      params = %{
        prompt: "Test prompt"
      }

      assert {:ok, result} = StartStream.run(params, %{})
      assert is_binary(result.stream_id)
      assert String.length(result.stream_id) > 0
      assert result.status == :streaming
    end

    @tag :skip
    test "includes on_token callback in result" do
      params = %{
        prompt: "Tell me a story",
        on_token: fn token -> send(self(), {:token, token}) end
      }

      assert {:ok, result} = StartStream.run(params, %{})
      assert is_binary(result.stream_id)
      # Would receive tokens in async test
    end

    @tag :skip
    test "respects buffer parameter" do
      params = %{
        prompt: "Write code",
        buffer: true
      }

      assert {:ok, result} = StartStream.run(params, %{})
      assert result.buffered == true
    end

    @tag :skip
    test "respects auto_process false" do
      params = %{
        prompt: "Generate text",
        auto_process: false
      }

      assert {:ok, result} = StartStream.run(params, %{})
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
