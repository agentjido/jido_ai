defmodule Jido.AI.Actions.Streaming.EndStreamTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Streaming.EndStream

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert EndStream.schema().fields[:stream_id].meta.required == true
      refute EndStream.schema().fields[:wait_for_completion].meta.required
      refute EndStream.schema().fields[:timeout].meta.required
    end

    test "has default values" do
      assert EndStream.schema().fields[:wait_for_completion].value == true
      assert EndStream.schema().fields[:timeout].value == 30_000
    end
  end

  describe "run/2" do
    test "returns error when stream_id is missing" do
      assert {:error, :stream_id_required} = EndStream.run(%{}, %{})
    end

    test "returns error when stream_id is empty string" do
      assert {:error, :stream_id_required} = EndStream.run(%{stream_id: ""}, %{})
    end

    test "returns error for invalid stream_id type" do
      assert {:error, :invalid_stream_id} = EndStream.run(%{stream_id: 123}, %{})
    end

    test "finalizes stream with valid stream_id" do
      params = %{
        stream_id: "test_stream_123"
      }

      assert {:ok, result} = EndStream.run(params, %{})
      assert result.stream_id == "test_stream_123"
      assert result.status == :completed
      assert is_map(result.usage)
    end

    test "respects wait_for_completion parameter" do
      params = %{
        stream_id: "test_stream_123",
        wait_for_completion: false
      }

      assert {:ok, result} = EndStream.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end

    test "respects timeout parameter" do
      params = %{
        stream_id: "test_stream_123",
        timeout: 5000
      }

      assert {:ok, result} = EndStream.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end
  end

  describe "usage extraction" do
    test "returns usage map" do
      params = %{
        stream_id: "test_stream_123"
      }

      assert {:ok, result} = EndStream.run(params, %{})
      assert Map.has_key?(result, :usage)
      assert Map.has_key?(result.usage, :input_tokens)
      assert Map.has_key?(result.usage, :output_tokens)
      assert Map.has_key?(result.usage, :total_tokens)
    end
  end
end
