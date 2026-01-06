defmodule Jido.AI.Skills.Streaming.Actions.ProcessTokensTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Streaming.Actions.ProcessTokens

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert ProcessTokens.schema()[:stream_id][:required] == true
      refute ProcessTokens.schema()[:on_token][:required]
      refute ProcessTokens.schema()[:filter][:required]
    end
  end

  describe "run/2" do
    test "returns error when stream_id is missing" do
      assert {:error, :stream_id_required} = ProcessTokens.run(%{}, %{})
    end

    test "returns error when stream_id is empty string" do
      assert {:error, :stream_id_required} = ProcessTokens.run(%{stream_id: ""}, %{})
    end

    test "returns error for invalid stream_id type" do
      assert {:error, :invalid_stream_id} = ProcessTokens.run(%{stream_id: 123}, %{})
    end

    test "processes with valid stream_id" do
      params = %{
        stream_id: "test_stream_123"
      }

      assert {:ok, result} = ProcessTokens.run(params, %{})
      assert result.stream_id == "test_stream_123"
      assert result.status == :processing
      assert is_integer(result.token_count)
    end

    test "accepts on_token callback" do
      callback = fn token -> send(self(), {:token, token}) end

      params = %{
        stream_id: "test_stream_123",
        on_token: callback
      }

      assert {:ok, result} = ProcessTokens.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end

    test "accepts filter function" do
      filter = fn token -> String.length(token) > 0 end

      params = %{
        stream_id: "test_stream_123",
        filter: filter
      }

      assert {:ok, result} = ProcessTokens.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end

    test "accepts transform function" do
      transform = fn token -> String.upcase(token) end

      params = %{
        stream_id: "test_stream_123",
        transform: transform
      }

      assert {:ok, result} = ProcessTokens.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end
  end

  describe "on_complete callback" do
    test "accepts on_complete callback" do
      callback = fn result -> send(self(), {:complete, result}) end

      params = %{
        stream_id: "test_stream_123",
        on_complete: callback
      }

      assert {:ok, result} = ProcessTokens.run(params, %{})
      assert result.stream_id == "test_stream_123"
    end
  end
end
