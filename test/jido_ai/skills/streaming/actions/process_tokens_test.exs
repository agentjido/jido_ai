defmodule Jido.AI.Actions.Streaming.ProcessTokensTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Streaming.ProcessTokens
  alias Jido.AI.Streaming.Registry
  alias Jido.AI.TestSupport.FakeLLMClient

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert ProcessTokens.schema().fields[:stream_id].meta.required == true
      refute ProcessTokens.schema().fields[:on_token].meta.required
      refute ProcessTokens.schema().fields[:filter].meta.required
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

    test "returns error when stream is not found" do
      assert {:error, :stream_not_found} =
               ProcessTokens.run(%{stream_id: "missing_stream"}, %{llm_client: FakeLLMClient})
    end

    test "processes tokens for a registered stream" do
      stream_id = unique_stream_id()
      register_stream(stream_id)

      assert {:ok, result} = ProcessTokens.run(%{stream_id: stream_id}, %{llm_client: FakeLLMClient})
      assert result.stream_id == stream_id
      assert result.status == :completed
      assert result.token_count == 3
      assert result.text == "abc"
      assert result.usage.total_tokens > 0
    end

    test "accepts on_token callback" do
      stream_id = unique_stream_id()
      register_stream(stream_id)

      callback = fn token -> send(self(), {:token, token}) end

      assert {:ok, result} =
               ProcessTokens.run(%{stream_id: stream_id, on_token: callback}, %{llm_client: FakeLLMClient})

      assert result.stream_id == stream_id
      assert_received {:token, "a"}
      assert_received {:token, "b"}
      assert_received {:token, "c"}
    end

    test "accepts filter function" do
      stream_id = unique_stream_id()
      register_stream(stream_id)

      filter = fn token -> token != "b" end

      assert {:ok, result} =
               ProcessTokens.run(%{stream_id: stream_id, filter: filter}, %{llm_client: FakeLLMClient})

      assert result.stream_id == stream_id
      assert result.token_count == 2
      assert result.text == "ac"
    end

    test "accepts transform function" do
      stream_id = unique_stream_id()
      register_stream(stream_id)

      transform = fn token -> String.upcase(token) end

      assert {:ok, result} =
               ProcessTokens.run(%{stream_id: stream_id, transform: transform}, %{llm_client: FakeLLMClient})

      assert result.stream_id == stream_id
      assert result.text == "ABC"
    end
  end

  describe "on_complete callback" do
    test "accepts on_complete callback" do
      stream_id = unique_stream_id()
      register_stream(stream_id)

      callback = fn result -> send(self(), {:complete, result}) end

      assert {:ok, result} =
               ProcessTokens.run(%{stream_id: stream_id, on_complete: callback}, %{llm_client: FakeLLMClient})

      assert result.stream_id == stream_id
      assert_received {:complete, %{stream_id: ^stream_id, status: :completed}}
    end
  end

  defp register_stream(stream_id) do
    {:ok, _entry} =
      Registry.register(stream_id, %{
        status: :pending,
        buffered: true,
        stream_response: %{
          chunks: ["a", "b", "c"],
          final: %{
            message: %{content: "abc", tool_calls: nil},
            finish_reason: :stop,
            usage: %{input_tokens: 5, output_tokens: 3}
          }
        }
      })
  end

  defp unique_stream_id do
    "stream_#{System.unique_integer([:positive])}"
  end
end
