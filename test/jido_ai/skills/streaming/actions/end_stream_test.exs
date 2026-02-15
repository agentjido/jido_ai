defmodule Jido.AI.Actions.Streaming.EndStreamTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Streaming.EndStream
  alias Jido.AI.Streaming.Registry

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

    test "returns error when stream is not found" do
      assert {:error, :stream_not_found} = EndStream.run(%{stream_id: "missing_stream"}, %{})
    end

    test "returns completed stream state for valid stream_id" do
      stream_id = unique_stream_id()
      register_completed_stream(stream_id)

      assert {:ok, result} = EndStream.run(%{stream_id: stream_id}, %{})
      assert result.stream_id == stream_id
      assert result.status == :completed
      assert is_map(result.usage)
      assert result.usage.total_tokens == 8
      assert result.text == "final text"
    end

    test "respects wait_for_completion false" do
      stream_id = unique_stream_id()
      register_pending_stream(stream_id)

      params = %{stream_id: stream_id, wait_for_completion: false}

      assert {:ok, result} = EndStream.run(params, %{})
      assert result.stream_id == stream_id
      assert result.status == :pending
    end

    test "respects timeout parameter" do
      stream_id = unique_stream_id()
      register_pending_stream(stream_id)

      params = %{stream_id: stream_id, timeout: 10}

      assert {:error, :timeout} = EndStream.run(params, %{})
    end
  end

  describe "usage extraction" do
    test "returns usage map" do
      stream_id = unique_stream_id()
      register_completed_stream(stream_id)

      assert {:ok, result} = EndStream.run(%{stream_id: stream_id}, %{})
      assert Map.has_key?(result, :usage)
      assert Map.has_key?(result.usage, :input_tokens)
      assert Map.has_key?(result.usage, :output_tokens)
      assert Map.has_key?(result.usage, :total_tokens)
    end
  end

  defp register_completed_stream(stream_id) do
    {:ok, _entry} =
      Registry.register(stream_id, %{
        status: :completed,
        text: "final text",
        usage: %{input_tokens: 5, output_tokens: 3, total_tokens: 8}
      })
  end

  defp register_pending_stream(stream_id) do
    {:ok, _entry} = Registry.register(stream_id, %{status: :pending})
  end

  defp unique_stream_id do
    "stream_#{System.unique_integer([:positive])}"
  end
end
