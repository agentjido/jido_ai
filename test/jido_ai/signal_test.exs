defmodule Jido.AI.SignalTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Signal, as: ReactSignal
  alias Jido.AI.Signal.{LLMDelta, LLMError, LLMResponse, Usage}

  describe "ReactEvent" do
    test "creates worker event signal with required fields" do
      signal =
        ReactSignal.new!(%{
          request_id: "req_123",
          event: %{id: "evt_1", kind: :llm_started}
        })

      assert signal.type == "ai.react.worker.event"
      assert signal.source == "/ai/react/worker"
      assert signal.data.request_id == "req_123"
      assert signal.data.event.kind == :llm_started
    end
  end

  describe "LLMResponse" do
    test "creates signal with required fields" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_123",
          result: {:ok, %{type: :final_answer, text: "Hello", tool_calls: []}}
        })

      assert signal.type == "ai.llm.response"
      assert signal.data.call_id == "call_123"
      assert signal.data.result == {:ok, %{type: :final_answer, text: "Hello", tool_calls: []}}
    end

    test "creates signal with usage metadata" do
      usage = %{input_tokens: 100, output_tokens: 50}

      signal =
        LLMResponse.new!(%{
          call_id: "call_456",
          result: {:ok, %{type: :final_answer, text: "Hi"}},
          usage: usage
        })

      assert signal.data.usage == usage
    end

    test "creates signal with model metadata" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_789",
          result: {:ok, %{type: :final_answer, text: "Hi"}},
          model: "anthropic:claude-haiku-4-5"
        })

      assert signal.data.model == "anthropic:claude-haiku-4-5"
    end

    test "creates signal with duration_ms metadata" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_abc",
          result: {:ok, %{type: :final_answer, text: "Hi"}},
          duration_ms: 1500
        })

      assert signal.data.duration_ms == 1500
    end

    test "creates signal with thinking_content metadata" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_def",
          result: {:ok, %{type: :final_answer, text: "Hi"}},
          thinking_content: "Let me think about this..."
        })

      assert signal.data.thinking_content == "Let me think about this..."
    end

    test "creates signal with all metadata fields" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_full",
          result: {:ok, %{type: :final_answer, text: "Complete"}},
          usage: %{input_tokens: 200, output_tokens: 100},
          model: "openai:gpt-4o",
          duration_ms: 2500,
          thinking_content: "I need to consider multiple options..."
        })

      assert signal.data.call_id == "call_full"
      assert signal.data.usage == %{input_tokens: 200, output_tokens: 100}
      assert signal.data.model == "openai:gpt-4o"
      assert signal.data.duration_ms == 2500
      assert signal.data.thinking_content == "I need to consider multiple options..."
    end
  end

  describe "LLMDelta" do
    test "creates partial signal with required fields" do
      signal =
        LLMDelta.new!(%{
          call_id: "call_partial_1",
          delta: "Hello"
        })

      assert signal.type == "ai.llm.delta"
      assert signal.data.call_id == "call_partial_1"
      assert signal.data.delta == "Hello"
      assert signal.data.chunk_type == :content
    end

    test "creates partial signal with default chunk_type :content" do
      signal =
        LLMDelta.new!(%{
          call_id: "call_partial_2",
          delta: " world"
        })

      assert signal.data.chunk_type == :content
    end

    test "creates partial signal with chunk_type :thinking" do
      signal =
        LLMDelta.new!(%{
          call_id: "call_partial_3",
          delta: "Let me think about this...",
          chunk_type: :thinking
        })

      assert signal.data.chunk_type == :thinking
      assert signal.data.delta == "Let me think about this..."
    end

    test "creates partial signal with empty delta" do
      signal =
        LLMDelta.new!(%{
          call_id: "call_partial_4",
          delta: ""
        })

      assert signal.data.delta == ""
    end

    test "creates multiple partial signals for streaming" do
      chunks = ["Hello", ", ", "world", "!"]

      signals =
        Enum.map(chunks, fn chunk ->
          LLMDelta.new!(%{
            call_id: "call_stream_1",
            delta: chunk
          })
        end)

      assert length(signals) == 4
      assert Enum.all?(signals, &(&1.type == "ai.llm.delta"))
      assert Enum.all?(signals, &(&1.data.call_id == "call_stream_1"))

      accumulated = signals |> Enum.map_join(& &1.data.delta)
      assert accumulated == "Hello, world!"
    end
  end

  describe "LLMError" do
    test "creates error signal with required fields" do
      signal =
        LLMError.new!(%{
          call_id: "call_err_1",
          error_type: :rate_limit,
          message: "Rate limit exceeded"
        })

      assert signal.type == "ai.llm.error"
      assert signal.data.call_id == "call_err_1"
      assert signal.data.error_type == :rate_limit
      assert signal.data.message == "Rate limit exceeded"
      assert signal.data.details == %{}
    end

    test "creates error signal with retry_after" do
      signal =
        LLMError.new!(%{
          call_id: "call_err_2",
          error_type: :rate_limit,
          message: "Too many requests",
          retry_after: 60
        })

      assert signal.data.retry_after == 60
    end

    test "creates error signal with details" do
      details = %{provider: "anthropic", error_code: "overloaded"}

      signal =
        LLMError.new!(%{
          call_id: "call_err_3",
          error_type: :provider_error,
          message: "Provider is overloaded",
          details: details
        })

      assert signal.data.details == details
    end

    test "supports all error types" do
      error_types = [:rate_limit, :auth, :timeout, :provider_error, :validation, :network, :unknown]

      for error_type <- error_types do
        signal =
          LLMError.new!(%{
            call_id: "call_#{error_type}",
            error_type: error_type,
            message: "Error of type #{error_type}"
          })

        assert signal.data.error_type == error_type
      end
    end
  end

  describe "Usage" do
    test "creates usage report with required fields" do
      signal =
        Usage.new!(%{
          call_id: "call_usage_1",
          model: "anthropic:claude-haiku-4-5",
          input_tokens: 150,
          output_tokens: 75
        })

      assert signal.type == "ai.usage"
      assert signal.data.call_id == "call_usage_1"
      assert signal.data.model == "anthropic:claude-haiku-4-5"
      assert signal.data.input_tokens == 150
      assert signal.data.output_tokens == 75
      assert signal.data.metadata == %{}
    end

    test "creates usage report with total_tokens" do
      signal =
        Usage.new!(%{
          call_id: "call_usage_2",
          model: "openai:gpt-4o",
          input_tokens: 200,
          output_tokens: 100,
          total_tokens: 300
        })

      assert signal.data.total_tokens == 300
    end

    test "creates usage report with duration_ms" do
      signal =
        Usage.new!(%{
          call_id: "call_usage_3",
          model: "openai:gpt-4o",
          input_tokens: 100,
          output_tokens: 50,
          duration_ms: 1200
        })

      assert signal.data.duration_ms == 1200
    end

    test "creates usage report with metadata" do
      metadata = %{request_id: "req_123", user_id: "user_456"}

      signal =
        Usage.new!(%{
          call_id: "call_usage_4",
          model: "anthropic:claude-sonnet-4-20250514",
          input_tokens: 500,
          output_tokens: 250,
          metadata: metadata
        })

      assert signal.data.metadata == metadata
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from successful result with tool_calls type" do
      tool_calls = [
        %{id: "tc_1", name: "calculator", arguments: %{a: 1, b: 2}},
        %{id: "tc_2", name: "weather", arguments: %{city: "NYC"}}
      ]

      signal =
        LLMResponse.new!(%{
          call_id: "call_tc_1",
          result: {:ok, %{type: :tool_calls, tool_calls: tool_calls, text: ""}}
        })

      assert LLMResponse.extract_tool_calls(signal) == tool_calls
    end

    test "extracts tool calls when type is not explicitly :tool_calls but list is present" do
      tool_calls = [%{id: "tc_3", name: "search", arguments: %{query: "test"}}]

      signal =
        LLMResponse.new!(%{
          call_id: "call_tc_2",
          result: {:ok, %{tool_calls: tool_calls, text: "Some text"}}
        })

      assert LLMResponse.extract_tool_calls(signal) == tool_calls
    end

    test "returns empty list for final_answer type" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_tc_3",
          result: {:ok, %{type: :final_answer, text: "Hello", tool_calls: []}}
        })

      assert LLMResponse.extract_tool_calls(signal) == []
    end

    test "returns empty list for error result" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_tc_4",
          result: {:error, %{reason: "timeout"}}
        })

      assert LLMResponse.extract_tool_calls(signal) == []
    end

    test "returns empty list for non-LLMResponse signals" do
      signal =
        Usage.new!(%{
          call_id: "call_usage",
          model: "test",
          input_tokens: 10,
          output_tokens: 5
        })

      assert LLMResponse.extract_tool_calls(signal) == []
    end
  end

  describe "tool_call?/1" do
    test "returns true for result with tool_calls type" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_is_tc_1",
          result: {:ok, %{type: :tool_calls, tool_calls: [%{id: "tc_1"}], text: ""}}
        })

      assert LLMResponse.tool_call?(signal) == true
    end

    test "returns true when tool_calls list is non-empty" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_is_tc_2",
          result: {:ok, %{tool_calls: [%{id: "tc_1"}], text: "text"}}
        })

      assert LLMResponse.tool_call?(signal) == true
    end

    test "returns false for final_answer type" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_is_tc_3",
          result: {:ok, %{type: :final_answer, text: "Hello", tool_calls: []}}
        })

      assert LLMResponse.tool_call?(signal) == false
    end

    test "returns false for error result" do
      signal =
        LLMResponse.new!(%{
          call_id: "call_is_tc_4",
          result: {:error, %{reason: "failed"}}
        })

      assert LLMResponse.tool_call?(signal) == false
    end

    test "returns false for non-LLMResponse signals" do
      signal =
        LLMError.new!(%{
          call_id: "call_err",
          error_type: :timeout,
          message: "Timeout"
        })

      assert LLMResponse.tool_call?(signal) == false
    end
  end

  describe "from_reqllm_response/2" do
    test "creates signal from simple text response" do
      response = %{
        message: %{content: "Hello, world!"},
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_1")

      assert signal.type == "ai.llm.response"
      assert signal.data.call_id == "call_from_1"
      assert {:ok, result} = signal.data.result
      assert result.type == :final_answer
      assert result.text == "Hello, world!"
      assert result.tool_calls == []
      assert signal.data.usage == %{input_tokens: 10, output_tokens: 5}
    end

    test "creates signal with model from response" do
      response = %{
        message: %{content: "Test"},
        model: "anthropic:claude-haiku-4-5"
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_2")

      assert signal.data.model == "anthropic:claude-haiku-4-5"
    end

    test "creates signal with model override" do
      response = %{
        message: %{content: "Test"},
        model: "anthropic:claude-haiku-4-5"
      }

      {:ok, signal} =
        LLMResponse.from_reqllm_response(response,
          call_id: "call_from_3",
          model: "openai:gpt-4o"
        )

      assert signal.data.model == "openai:gpt-4o"
    end

    test "creates signal with duration_ms" do
      response = %{message: %{content: "Test"}}

      {:ok, signal} =
        LLMResponse.from_reqllm_response(response,
          call_id: "call_from_4",
          duration_ms: 1234
        )

      assert signal.data.duration_ms == 1234
    end

    test "handles content as list with text blocks" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "First part. "},
            %{type: :text, text: "Second part."}
          ]
        }
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_5")

      {:ok, result} = signal.data.result
      assert result.text == "First part. \nSecond part."
    end

    test "extracts thinking content from response" do
      response = %{
        message: %{
          content: [
            %{type: :thinking, thinking: "Let me analyze this..."},
            %{type: :text, text: "Here is my answer."}
          ]
        }
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_6")

      assert signal.data.thinking_content == "Let me analyze this..."
      {:ok, result} = signal.data.result
      assert result.text == "Here is my answer."
    end

    test "handles tool calls in response" do
      response = %{
        message: %{
          content: "",
          tool_calls: [
            %{id: "tc_resp_1", name: "calculator", arguments: %{x: 5}}
          ]
        }
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_7")

      {:ok, result} = signal.data.result
      assert result.type == :tool_calls
      assert length(result.tool_calls) == 1
      [tc] = result.tool_calls
      assert tc.id == "tc_resp_1"
      assert tc.name == "calculator"
      assert tc.arguments == %{x: 5}
    end

    test "handles usage with string keys" do
      response = %{
        message: %{content: "Test"},
        usage: %{"input_tokens" => 20, "output_tokens" => 10}
      }

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_8")

      assert signal.data.usage == %{input_tokens: 20, output_tokens: 10}
    end

    test "handles response without usage" do
      response = %{message: %{content: "No usage"}}

      {:ok, signal} = LLMResponse.from_reqllm_response(response, call_id: "call_from_9")

      # usage key is not present when nil
      refute Map.has_key?(signal.data, :usage)
    end

    test "raises when call_id is missing" do
      response = %{message: %{content: "Test"}}

      assert_raise KeyError, fn ->
        LLMResponse.from_reqllm_response(response, [])
      end
    end
  end
end
