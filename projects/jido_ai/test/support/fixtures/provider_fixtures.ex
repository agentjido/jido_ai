defmodule Jido.AI.Test.Fixtures.ProviderFixtures do
  @moduledoc """
  Test fixtures for AI providers and HTTP responses.

  Provides centralized provider configurations, HTTP response bodies,
  and helpers for different response scenarios.
  """

  alias JidoAI.Provider.Test

  @doc """
  Returns a test provider configuration.
  """
  def test_provider(name, opts \\ []) do
    base_config = %{
      name: name,
      module: Keyword.get(opts, :module, Test),
      api_key_name: to_string(name),
      base_url: Keyword.get(opts, :base_url, "https://api.#{name}.com"),
      headers: Keyword.get(opts, :headers, %{"Content-Type" => "application/json"}),
      models: Keyword.get(opts, :models, ["test-model-1", "test-model-2"])
    }

    Map.merge(base_config, Map.new(opts))
  end

  # OpenAI Response Fixtures

  @doc """
  Returns a mock OpenAI chat completion response.
  """
  def openai_response(content \\ "Test response", opts \\ []) do
    %{
      "id" => opts[:id] || "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => opts[:created] || System.system_time(:second),
      "model" => opts[:model] || "gpt-4",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => opts[:finish_reason] || "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => opts[:prompt_tokens] || 10,
        "completion_tokens" => opts[:completion_tokens] || 20,
        "total_tokens" => opts[:total_tokens] || 30
      }
    }
  end

  @doc """
  Returns a mock OpenAI streaming chunk response.
  """
  def openai_stream_chunk(content \\ "chunk", opts \\ []) do
    %{
      "id" => opts[:id] || "chatcmpl-test123",
      "object" => "chat.completion.chunk",
      "created" => opts[:created] || System.system_time(:second),
      "model" => opts[:model] || "gpt-4",
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{
            "content" => content
          },
          "finish_reason" => opts[:finish_reason]
        }
      ]
    }
  end

  @doc """
  Returns a mock OpenAI error response.
  """
  def openai_error(message \\ "Test error", opts \\ []) do
    %{
      "error" => %{
        "message" => message,
        "type" => opts[:type] || "invalid_request_error",
        "code" => opts[:code]
      }
    }
  end

  # Anthropic Response Fixtures

  @doc """
  Returns a mock Anthropic message response.
  """
  def anthropic_response(content \\ "Test response", opts \\ []) do
    %{
      "id" => opts[:id] || "msg_test123",
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => content}],
      "model" => opts[:model] || "claude-3-opus-20240229",
      "stop_reason" => opts[:stop_reason] || "end_turn",
      "stop_sequence" => opts[:stop_sequence],
      "usage" => %{
        "input_tokens" => opts[:input_tokens] || 10,
        "output_tokens" => opts[:output_tokens] || 20
      }
    }
  end

  @doc """
  Returns a mock Anthropic streaming event.
  """
  def anthropic_stream_event(content \\ "chunk", opts \\ []) do
    case opts[:type] || "content_block_delta" do
      "content_block_delta" ->
        %{
          "type" => "content_block_delta",
          "index" => opts[:index] || 0,
          "delta" => %{
            "type" => "text_delta",
            "text" => content
          }
        }

      "message_start" ->
        %{
          "type" => "message_start",
          "message" => anthropic_response("", opts)
        }

      "message_stop" ->
        %{
          "type" => "message_stop"
        }
    end
  end

  @doc """
  Returns a mock Anthropic error response.
  """
  def anthropic_error(message \\ "Test error", opts \\ []) do
    %{
      "type" => "error",
      "error" => %{
        "type" => opts[:type] || "invalid_request_error",
        "message" => message
      }
    }
  end

  # Google Gemini Response Fixtures

  @doc """
  Returns a mock Google Gemini response.
  """
  def gemini_response(content \\ "Test response", opts \\ []) do
    %{
      "candidates" => [
        %{
          "content" => %{
            "parts" => [%{"text" => content}],
            "role" => "model"
          },
          "finishReason" => opts[:finish_reason] || "STOP",
          "index" => opts[:index] || 0
        }
      ],
      "usageMetadata" => %{
        "promptTokenCount" => opts[:prompt_tokens] || 10,
        "candidatesTokenCount" => opts[:completion_tokens] || 20,
        "totalTokenCount" => opts[:total_tokens] || 30
      }
    }
  end

  @doc """
  Returns a mock Google Gemini streaming chunk.
  """
  def gemini_stream_chunk(content \\ "chunk", opts \\ []) do
    %{
      "candidates" => [
        %{
          "content" => %{
            "parts" => [%{"text" => content}],
            "role" => "model"
          },
          "index" => opts[:index] || 0
        }
      ]
    }
  end

  @doc """
  Returns a mock Google Gemini error response.
  """
  def gemini_error(message \\ "Test error", opts \\ []) do
    %{
      "error" => %{
        "code" => opts[:code] || 400,
        "message" => message,
        "status" => opts[:status] || "INVALID_ARGUMENT"
      }
    }
  end

  # Mistral Response Fixtures

  @doc """
  Returns a mock Mistral response.
  """
  def mistral_response(content \\ "Test response", opts \\ []) do
    %{
      "id" => opts[:id] || "cmpl-test123",
      "object" => "chat.completion",
      "created" => opts[:created] || System.system_time(:second),
      "model" => opts[:model] || "mistral-large",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => opts[:finish_reason] || "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => opts[:prompt_tokens] || 10,
        "completion_tokens" => opts[:completion_tokens] || 20,
        "total_tokens" => opts[:total_tokens] || 30
      }
    }
  end

  # Generic Response Fixtures

  @doc """
  Returns a generic success response structure.
  """
  def success_response(content \\ "Generated response") do
    %{
      "choices" => [
        %{"message" => %{"content" => content}}
      ]
    }
  end

  @doc """
  Returns a generic error response structure.
  """
  def error_response(message \\ "Test error", opts \\ []) do
    %{
      "error" => %{
        "message" => message,
        "type" => opts[:type] || "test_error",
        "code" => opts[:code]
      }
    }
  end

  # SSE Response Helpers

  @doc """
  Formats content chunks as SSE data for testing streaming.
  """
  def sse_chunks(content_chunks) do
    Enum.map(content_chunks, fn content ->
      "data: {\"choices\":[{\"delta\":{\"content\":\"#{content}\"}}]}\n\n"
    end) ++ ["data: [DONE]\n\n"]
  end

  @doc """
  Returns SSE stream data for OpenAI format.
  """
  def openai_sse_stream(content_chunks) do
    content_chunks
    |> Enum.map(fn content ->
      chunk = openai_stream_chunk(content)
      "data: #{Jason.encode!(chunk)}\n\n"
    end)
    |> Kernel.++([
      "data: #{Jason.encode!(openai_stream_chunk("", finish_reason: "stop"))}\n\n",
      "data: [DONE]\n\n"
    ])
  end

  @doc """
  Returns SSE stream data for Anthropic format.
  """
  def anthropic_sse_stream(content_chunks) do
    start_event = "data: #{Jason.encode!(anthropic_stream_event("", type: "message_start"))}\n\n"

    content_events =
      Enum.map(content_chunks, fn content ->
        event = anthropic_stream_event(content, type: "content_block_delta")
        "data: #{Jason.encode!(event)}\n\n"
      end)

    stop_event = "data: #{Jason.encode!(anthropic_stream_event("", type: "message_stop"))}\n\n"

    [start_event] ++ content_events ++ [stop_event]
  end

  # JSON-encoded versions for HTTP mocking

  @doc """
  Returns JSON-encoded OpenAI response.
  """
  def openai_json(content \\ "Test response", opts \\ []) do
    content
    |> openai_response(opts)
    |> Jason.encode!()
  end

  @doc """
  Returns JSON-encoded Anthropic response.
  """
  def anthropic_json(content \\ "Test response", opts \\ []) do
    content
    |> anthropic_response(opts)
    |> Jason.encode!()
  end

  @doc """
  Returns JSON-encoded Gemini response.
  """
  def gemini_json(content \\ "Test response", opts \\ []) do
    content
    |> gemini_response(opts)
    |> Jason.encode!()
  end

  @doc """
  Returns JSON-encoded Mistral response.
  """
  def mistral_json(content \\ "Test response", opts \\ []) do
    content
    |> mistral_response(opts)
    |> Jason.encode!()
  end
end
