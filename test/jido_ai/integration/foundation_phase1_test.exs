defmodule Jido.AI.Integration.FoundationPhase1Test do
  @moduledoc """
  Integration tests for Phase 1 Foundation Enhancement.

  These tests verify that all Phase 1 components work together correctly:
  - Configuration (model aliases, defaults, provider config)
  - Directives (ReqLLMStream, ReqLLMGenerate, ReqLLMEmbed)
  - Signals (ReqLLMResult, ReqLLMError, UsageReport, ToolResult, EmbedResult)
  - Helpers (message building, response processing, error handling)
  - Tool Adapter (action registry, tool conversion)

  Tests use mocked response data and do not make actual API calls.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Directive.{ReqLLMEmbed, ReqLLMGenerate, ReqLLMStream}
  alias Jido.AI.Helpers
  alias Jido.AI.Signal
  alias Jido.AI.Signal.{EmbedResult, ReqLLMError, ToolResult, UsageReport}
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Tools.Executor
  alias ReqLLM.Context

  # ============================================================================
  # Directive + Configuration Integration
  # ============================================================================

  describe "directive with config integration" do
    test "ReqLLMStream uses model_alias resolution" do
      # Create directive with model_alias
      directive =
        ReqLLMStream.new!(%{
          id: "stream_1",
          model_alias: :fast,
          context: [%{role: :user, content: "Hello"}]
        })

      assert directive.model_alias == :fast
      assert is_nil(directive.model)

      # Resolve the model alias via Config
      resolved_model = Jido.AI.resolve_model(directive.model_alias)
      assert is_binary(resolved_model)
      assert String.contains?(resolved_model, ":")
    end

    test "ReqLLMGenerate uses model_alias resolution" do
      directive =
        ReqLLMGenerate.new!(%{
          id: "gen_1",
          model_alias: :capable,
          context: [%{role: :user, content: "Explain this"}]
        })

      resolved_model = Jido.AI.resolve_model(directive.model_alias)
      assert is_binary(resolved_model)
    end

    test "directive with direct model bypasses alias resolution" do
      model = "anthropic:claude-haiku-4-5"

      directive =
        ReqLLMStream.new!(%{
          id: "stream_2",
          model: model,
          context: [%{role: :user, content: "Hello"}]
        })

      # Direct model passes through Jido.AI.resolve_model unchanged
      assert Jido.AI.resolve_model(directive.model) == model
    end

    test "directive has default values" do
      directive =
        ReqLLMStream.new!(%{
          id: "stream_3",
          model: "test:model",
          context: [%{role: :user, content: "Hello"}]
        })

      # Directive has its own defaults
      assert is_number(directive.temperature)
      assert is_integer(directive.max_tokens)
    end

    test "ReqLLMEmbed directive creation" do
      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_1",
          model: "openai:text-embedding-3-small",
          texts: ["Hello", "World"]
        })

      assert directive.id == "embed_1"
      assert directive.texts == ["Hello", "World"]
    end
  end

  # ============================================================================
  # Signal Flow Integration
  # ============================================================================

  describe "signal creation from mocked responses" do
    test "from_reqllm_response creates signal with text content" do
      mocked_response = %{
        message: %{content: "Hello, I'm an AI assistant!"},
        usage: %{input_tokens: 10, output_tokens: 15},
        model: "anthropic:claude-haiku-4-5"
      }

      {:ok, signal} =
        Signal.from_reqllm_response(mocked_response,
          call_id: "call_123",
          duration_ms: 500
        )

      assert signal.type == "reqllm.result"
      assert signal.data.call_id == "call_123"
      assert signal.data.duration_ms == 500
      assert signal.data.model == "anthropic:claude-haiku-4-5"
      assert signal.data.usage == %{input_tokens: 10, output_tokens: 15}

      {:ok, result} = signal.data.result
      assert result.type == :final_answer
      assert result.text == "Hello, I'm an AI assistant!"
      assert result.tool_calls == []
    end

    test "from_reqllm_response creates signal with tool calls" do
      mocked_response = %{
        message: %{
          content: "",
          tool_calls: [
            %{id: "tc_1", name: "calculator", arguments: %{a: 1, b: 2}},
            %{id: "tc_2", name: "weather", arguments: %{city: "NYC"}}
          ]
        },
        usage: %{input_tokens: 20, output_tokens: 30}
      }

      {:ok, signal} = Signal.from_reqllm_response(mocked_response, call_id: "call_456")

      {:ok, result} = signal.data.result
      assert result.type == :tool_calls
      assert length(result.tool_calls) == 2

      [tc1, tc2] = result.tool_calls
      assert tc1.name == "calculator"
      assert tc2.name == "weather"
    end

    test "signal helper functions work with created signals" do
      mocked_response = %{
        message: %{
          content: "",
          tool_calls: [%{id: "tc_1", name: "search", arguments: %{query: "test"}}]
        }
      }

      {:ok, signal} = Signal.from_reqllm_response(mocked_response, call_id: "call_789")

      # Test helper functions
      assert Signal.tool_call?(signal) == true
      tool_calls = Signal.extract_tool_calls(signal)
      assert length(tool_calls) == 1
      assert hd(tool_calls).name == "search"
    end

    test "final answer signal helper functions" do
      mocked_response = %{
        message: %{content: "The answer is 42."}
      }

      {:ok, signal} = Signal.from_reqllm_response(mocked_response, call_id: "call_answer")

      assert Signal.tool_call?(signal) == false
      assert Signal.extract_tool_calls(signal) == []
    end
  end

  describe "error signal integration" do
    test "ReqLLMError signal creation" do
      error_signal =
        ReqLLMError.new!(%{
          call_id: "call_err_1",
          error_type: :rate_limit,
          message: "Rate limit exceeded",
          retry_after: 60
        })

      assert error_signal.type == "reqllm.error"
      assert error_signal.data.error_type == :rate_limit
      assert error_signal.data.retry_after == 60
    end

    test "Helpers.wrap_error creates proper Jido.AI.Error" do
      reqllm_error = %ReqLLM.Error.API.Request{
        status: 429,
        reason: "Too many requests"
      }

      {:error, jido_error} = Helpers.wrap_error(reqllm_error)

      assert %Jido.AI.Error.API.RateLimit{} = jido_error
      assert jido_error.message == "Too many requests"
    end

    test "error classification flows through helpers" do
      # classify_error uses status codes and reason atoms, not string reasons
      errors_and_types = [
        {%{status: 429}, :rate_limit},
        {%{status: 401}, :auth},
        {%{status: 500}, :provider_error},
        {%{reason: :timeout}, :timeout},
        {%{reason: :econnrefused}, :network}
      ]

      for {error, expected_type} <- errors_and_types do
        assert Helpers.classify_error(error) == expected_type
      end
    end
  end

  describe "usage report signal integration" do
    test "UsageReport signal with full metadata" do
      usage_signal =
        UsageReport.new!(%{
          call_id: "call_usage_1",
          model: "anthropic:claude-haiku-4-5",
          input_tokens: 100,
          output_tokens: 50,
          total_tokens: 150,
          duration_ms: 1200,
          metadata: %{request_id: "req_123"}
        })

      assert usage_signal.type == "ai.usage_report"
      assert usage_signal.data.model == "anthropic:claude-haiku-4-5"
      assert usage_signal.data.input_tokens == 100
      assert usage_signal.data.output_tokens == 50
      assert usage_signal.data.duration_ms == 1200
    end
  end

  describe "tool result signal integration" do
    test "ToolResult signal with successful result" do
      tool_signal =
        ToolResult.new!(%{
          call_id: "tc_calc_1",
          tool_name: "calculator",
          result: {:ok, %{answer: 42}}
        })

      assert tool_signal.type == "ai.tool_result"
      assert tool_signal.data.tool_name == "calculator"
      assert tool_signal.data.result == {:ok, %{answer: 42}}
    end

    test "ToolResult signal with error result" do
      tool_signal =
        ToolResult.new!(%{
          call_id: "tc_fail_1",
          tool_name: "search",
          result: {:error, %{reason: "Service unavailable"}}
        })

      assert tool_signal.data.result == {:error, %{reason: "Service unavailable"}}
    end
  end

  describe "embed result signal integration" do
    test "EmbedResult signal with embeddings" do
      embeddings = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]

      embed_signal =
        EmbedResult.new!(%{
          call_id: "embed_1",
          result: {:ok, %{embeddings: embeddings, count: 2}}
        })

      assert embed_signal.type == "ai.embed_result"
      {:ok, result} = embed_signal.data.result
      assert result.embeddings == embeddings
      assert result.count == 2
    end
  end

  # ============================================================================
  # Helpers Integration
  # ============================================================================

  describe "helpers with response processing" do
    test "classify_llm_response determines response type" do
      tool_response = %{
        message: %{content: nil, tool_calls: [%{id: "tc_1", name: "test", arguments: %{}}]},
        finish_reason: :tool_calls
      }

      text_response = %{
        message: %{content: "Hello", tool_calls: nil},
        finish_reason: :stop
      }

      tool_result = Helpers.classify_llm_response(tool_response)
      assert tool_result.type == :tool_calls

      text_result = Helpers.classify_llm_response(text_response)
      assert text_result.type == :final_answer
      assert text_result.text == "Hello"
    end
  end

  describe "message building with ReqLLM.Context" do
    test "Context.normalize creates valid context" do
      {:ok, context} = Context.normalize("Hello")

      assert %ReqLLM.Context{} = context
      assert length(context.messages) == 1
      [msg] = context.messages
      assert msg.role == :user
    end

    test "Context.normalize with system_prompt" do
      {:ok, context} = Context.normalize("Hello", system_prompt: "Be helpful")

      assert length(context.messages) == 2
      [system, user] = context.messages
      assert system.role == :system
      assert user.role == :user
    end

    test "Context.append with tool_result_message" do
      {:ok, context} = Context.normalize("Call calculator")
      tool_msg = Context.tool_result_message("calculator", "tc_1", %{result: 42})
      updated = Context.append(context, tool_msg)

      assert length(updated.messages) == 2
      [_user, tool] = updated.messages
      assert tool.role == :tool
      assert tool.tool_call_id == "tc_1"
    end
  end

  # ============================================================================
  # Tool Adapter Integration
  # ============================================================================

  describe "tool adapter integration" do
    defmodule TestAction do
      use Jido.Action,
        name: "test_action",
        description: "A test action for integration testing",
        schema: [
          input: [type: :string, required: true, doc: "Test input"]
        ]

      @impl true
      def run(_params, _context), do: {:ok, %{}}
    end

    test "build tools map and retrieve action" do
      tools_map = Executor.build_tools_map([TestAction])

      assert Map.has_key?(tools_map, "test_action")
      assert tools_map["test_action"] == TestAction
    end

    test "convert action modules to ReqLLM tools" do
      tools = [ToolAdapter.from_action(TestAction)]
      assert length(tools) == 1

      [tool] = tools
      assert tool.name == "test_action"
      assert tool.description == "A test action for integration testing"
    end
  end

  # ============================================================================
  # Configuration Integration
  # ============================================================================

  describe "configuration integration" do
    test "model aliases are consistently resolved" do
      # All default aliases should resolve to valid model specs
      for alias <- [:fast, :capable, :reasoning] do
        model = Jido.AI.resolve_model(alias)
        assert is_binary(model)
        assert String.contains?(model, ":")
      end
    end

    test "custom model alias configuration" do
      Application.put_env(:jido_ai, :model_aliases, %{
        custom_test: "test:custom-model"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :model_aliases) end)

      assert Jido.AI.resolve_model(:custom_test) == "test:custom-model"

      # Default aliases still work
      assert is_binary(Jido.AI.resolve_model(:fast))
    end
  end

  # ============================================================================
  # End-to-End Flow Tests
  # ============================================================================

  describe "end-to-end flow simulation" do
    test "complete request -> response -> signal flow" do
      # 1. Create directive with model alias
      directive =
        ReqLLMStream.new!(%{
          id: "e2e_1",
          model_alias: :fast,
          system_prompt: "You are helpful.",
          context: [%{role: :user, content: "What is 2+2?"}]
        })

      # 2. Resolve model for the request
      model = Jido.AI.resolve_model(directive.model_alias)
      assert is_binary(model)

      # 3. Simulate response (what we'd get from ReqLLM)
      mocked_response = %{
        message: %{content: "2 + 2 equals 4."},
        usage: %{input_tokens: 15, output_tokens: 10},
        model: model
      }

      # 4. Create signal from response
      {:ok, signal} =
        Signal.from_reqllm_response(mocked_response,
          call_id: directive.id,
          duration_ms: 250
        )

      # 5. Verify signal contains all expected data
      assert signal.data.call_id == "e2e_1"
      assert signal.data.model == model
      assert signal.data.duration_ms == 250

      # 6. Verify signal has no tool calls
      assert Signal.tool_call?(signal) == false
    end

    test "complete tool call flow" do
      # 1. Create directive
      directive =
        ReqLLMGenerate.new!(%{
          id: "tool_e2e_1",
          model: "test:model",
          context: [%{role: :user, content: "Calculate 5 * 7"}]
        })

      # 2. Simulate tool call response
      mocked_response = %{
        message: %{
          content: "",
          tool_calls: [%{id: "tc_mult", name: "calculator", arguments: %{a: 5, b: 7, op: "multiply"}}]
        },
        usage: %{input_tokens: 20, output_tokens: 15}
      }

      # 3. Create signal
      {:ok, signal} = Signal.from_reqllm_response(mocked_response, call_id: directive.id)

      # 4. Verify tool call detection
      assert Signal.tool_call?(signal) == true
      tool_calls = Signal.extract_tool_calls(signal)
      assert length(tool_calls) == 1

      [tc] = tool_calls
      assert tc.name == "calculator"

      # 5. Create tool result signal
      tool_result =
        ToolResult.new!(%{
          call_id: tc.id,
          tool_name: tc.name,
          result: {:ok, %{answer: 35}}
        })

      assert tool_result.data.result == {:ok, %{answer: 35}}

      # 6. Build context with tool result using ReqLLM.Context
      {:ok, context} = Context.normalize("Calculate 5 * 7")
      tool_msg = Context.tool_result_message(tc.name, tc.id, %{answer: 35})
      updated_context = Context.append(context, tool_msg)

      assert length(updated_context.messages) == 2
    end

    test "error handling flow" do
      # Simulate error with proper format for classify_error
      reqllm_error = %{
        status: 429,
        reason: "Rate limit exceeded",
        response_headers: [{"retry-after", "60"}]
      }

      # 1. Classify error
      assert Helpers.classify_error(reqllm_error) == :rate_limit

      # 2. Extract retry-after
      assert Helpers.extract_retry_after(reqllm_error) == 60

      # 3. Wrap to Jido.AI.Error
      {:error, jido_error} = Helpers.wrap_error(reqllm_error)
      assert %Jido.AI.Error.API.RateLimit{} = jido_error
      assert jido_error.retry_after == 60

      # 4. Create error signal
      error_signal =
        ReqLLMError.new!(%{
          call_id: "err_flow_1",
          error_type: :rate_limit,
          message: "Rate limit exceeded",
          retry_after: 60
        })

      assert error_signal.data.error_type == :rate_limit
    end
  end
end
