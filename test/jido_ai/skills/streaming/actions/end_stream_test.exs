defmodule Jido.AI.Skills.Streaming.Actions.EndStreamTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Streaming.Actions.EndStream

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert EndStream.schema()[:stream_id][:required] == true
      refute EndStream.schema()[:wait_for_completion][:required]
      refute EndStream.schema()[:timeout][:required]
    end

    test "has default values" do
      assert EndStream.schema()[:wait_for_completion][:default] == true
      assert EndStream.schema()[:timeout][:default] == 30000
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
