defmodule Jido.AI.ReqLlmBridge.ToolIntegrationManagerTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.{
    ConversationManager,
    ToolBuilder,
    ToolIntegrationManager,
    ToolResponseHandler
  }

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)
    Mimic.copy(ToolBuilder)
    Mimic.copy(ToolResponseHandler)
    Mimic.copy(ConversationManager)

    # ConversationManager is already started by the application
    # No need to start it again in tests

    # Mock Action for testing
    defmodule WeatherAction do
      use Jido.Action,
        name: "get_weather",
        description: "Gets the current weather for a location",
        schema: [
          location: [type: :string, required: true, doc: "The city or location"],
          units: [
            type: {:in, [:celsius, :fahrenheit]},
            default: :celsius,
            doc: "Temperature units"
          ]
        ]

      @impl true
      def run(params, _context) do
        weather_data = %{
          location: params.location,
          temperature: if(params.units == :celsius, do: 22, else: 72),
          condition: "sunny",
          units: params.units
        }

        {:ok, weather_data}
      end
    end

    defmodule CalculatorAction do
      use Jido.Action,
        name: "calculator",
        description: "Performs basic arithmetic operations",
        schema: [
          operation: [type: {:in, [:add, :subtract, :multiply, :divide]}, required: true],
          a: [type: :float, required: true],
          b: [type: :float, required: true]
        ]

      @impl true
      def run(params, _context) do
        result =
          case params.operation do
            :add -> params.a + params.b
            :subtract -> params.a - params.b
            :multiply -> params.a * params.b
            :divide when params.b != 0 -> params.a / params.b
            :divide -> {:error, "Division by zero"}
          end

        case result do
          {:error, _} = error -> error
          value -> {:ok, %{result: value, operation: params.operation}}
        end
      end
    end

    {:ok,
     %{
       weather_action: WeatherAction,
       calculator_action: CalculatorAction
     }}
  end

  describe "generate_with_tools/3" do
    test "successfully generates response with tool execution", %{weather_action: action} do
      # Mock tool conversion
      tool_descriptor = %{
        name: "get_weather",
        description: "Gets weather",
        parameter_schema: %{},
        callback: fn %{"location" => "Paris"} ->
          {:ok, %{location: "Paris", temperature: 22, condition: "sunny"}}
        end
      }

      expect(ToolBuilder, :batch_convert, fn [^action], _options ->
        {:ok, [tool_descriptor]}
      end)

      # Mock conversation creation
      expect(ConversationManager, :create_conversation, fn ->
        {:ok, "conv_123"}
      end)

      # Mock LLM request
      llm_response = %{
        content: "The weather in Paris is sunny with 22°C.",
        tool_calls: [
          %{
            id: "call_1",
            function: %{name: "get_weather", arguments: %{"location" => "Paris"}}
          }
        ],
        usage: %{prompt_tokens: 50, completion_tokens: 25, total_tokens: 75}
      }

      expect(ReqLLM, :generate_text, fn _model, _message, _options ->
        {:ok, llm_response}
      end)

      # Mock response processing
      processed_response = %{
        content: "The weather in Paris is sunny with 22°C.",
        tool_calls: [%{id: "call_1", function: %{name: "get_weather"}}],
        tool_results: [%{tool_call_id: "call_1", content: "sunny, 22°C"}],
        usage: %{total_tokens: 75},
        conversation_id: "conv_123",
        finished: true
      }

      expect(ToolResponseHandler, :process_llm_response, fn _response, _conv_id, _options ->
        {:ok, processed_response}
      end)

      # Execute the test
      options = %{model: "gpt-4", temperature: 0.7}

      assert {:ok, response} =
               ToolIntegrationManager.generate_with_tools(
                 "What's the weather in Paris?",
                 [action],
                 options
               )

      assert response.content == "The weather in Paris is sunny with 22°C."
      assert response.conversation_id == "conv_123"
      assert response.finished == true
    end

    test "handles tool conversion failure", %{weather_action: action} do
      expect(ToolBuilder, :batch_convert, fn [^action], _options ->
        {:error, "Tool conversion failed"}
      end)

      assert {:error, {:tool_conversion_failed, "Tool conversion failed"}} =
               ToolIntegrationManager.generate_with_tools("Test", [action])
    end

    test "handles LLM request failure", %{weather_action: action} do
      tool_descriptor = %{name: "test", callback: fn _ -> {:ok, %{}} end}

      expect(ToolBuilder, :batch_convert, fn _, _ -> {:ok, [tool_descriptor]} end)
      expect(ConversationManager, :create_conversation, fn -> {:ok, "conv_123"} end)

      expect(ReqLLM, :generate_text, fn _, _, _ ->
        {:error, "API request failed"}
      end)

      assert {:error, {:llm_request_failed, "API request failed"}} =
               ToolIntegrationManager.generate_with_tools("Test", [action])
    end

    test "validates options correctly" do
      # Test invalid model
      assert {:error, "Invalid model: must be a non-empty string"} =
               ToolIntegrationManager.generate_with_tools("Test", [], %{model: ""})

      # Test invalid temperature
      assert {:error, "Invalid temperature: must be between 0.0 and 2.0"} =
               ToolIntegrationManager.generate_with_tools("Test", [], %{temperature: 3.0})

      # Test invalid max_tokens
      assert {:error, "Invalid max_tokens: must be a positive integer"} =
               ToolIntegrationManager.generate_with_tools("Test", [], %{max_tokens: -1})
    end
  end

  describe "conversation management" do
    test "start_conversation/2 creates conversation with tools", %{weather_action: action} do
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      expect(ToolBuilder, :batch_convert, fn [^action], _options ->
        {:ok, [tool_descriptor]}
      end)

      expect(ConversationManager, :create_conversation, fn ->
        {:ok, "conv_456"}
      end)

      expect(ConversationManager, :set_tools, fn "conv_456", [^tool_descriptor] ->
        :ok
      end)

      expect(ConversationManager, :set_options, fn "conv_456", _options ->
        :ok
      end)

      assert {:ok, "conv_456"} = ToolIntegrationManager.start_conversation([action])
    end

    test "continue_conversation/3 processes message with context", %{weather_action: _action} do
      conversation_id = "conv_789"
      message = "What's the weather like?"

      # Mock getting conversation state
      conversation_options = %{model: "gpt-4", temperature: 0.7}
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      expect(ConversationManager, :get_options, fn ^conversation_id ->
        {:ok, conversation_options}
      end)

      expect(ConversationManager, :get_tools, fn ^conversation_id ->
        {:ok, [tool_descriptor]}
      end)

      expect(ConversationManager, :add_user_message, fn ^conversation_id, ^message ->
        :ok
      end)

      # Mock LLM response
      llm_response = %{content: "Weather response", usage: %{total_tokens: 50}}

      expect(ReqLLM, :generate_text, fn _model, ^message, _options ->
        {:ok, llm_response}
      end)

      # Mock response processing
      processed_response = %{
        content: "Weather response",
        conversation_id: conversation_id,
        finished: true
      }

      expect(ToolResponseHandler, :process_llm_response, fn _response,
                                                            ^conversation_id,
                                                            _options ->
        {:ok, processed_response}
      end)

      expect(ConversationManager, :add_assistant_response, fn ^conversation_id,
                                                              ^processed_response ->
        :ok
      end)

      assert {:ok, response} =
               ToolIntegrationManager.continue_conversation(
                 conversation_id,
                 message
               )

      assert response.conversation_id == conversation_id
    end

    test "get_conversation_history/1 retrieves messages" do
      conversation_id = "conv_history"

      messages = [
        %{role: "user", content: "Hello", timestamp: DateTime.utc_now()},
        %{role: "assistant", content: "Hi there!", timestamp: DateTime.utc_now()}
      ]

      expect(ConversationManager, :get_history, fn ^conversation_id ->
        {:ok, messages}
      end)

      assert {:ok, ^messages} = ToolIntegrationManager.get_conversation_history(conversation_id)
    end

    test "end_conversation/1 cleans up conversation" do
      conversation_id = "conv_end"

      expect(ConversationManager, :end_conversation, fn ^conversation_id ->
        :ok
      end)

      assert :ok = ToolIntegrationManager.end_conversation(conversation_id)
    end
  end

  describe "streaming support" do
    test "handles streaming requests", %{weather_action: action} do
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      expect(ToolBuilder, :batch_convert, fn [^action], _options ->
        {:ok, [tool_descriptor]}
      end)

      expect(ConversationManager, :create_conversation, fn ->
        {:ok, "conv_stream"}
      end)

      # Mock streaming response
      stream = [
        %{content: "The weather "},
        %{content: "is sunny"},
        %{tool_calls: [%{id: "call_1", function: %{name: "get_weather"}}]}
      ]

      expect(ReqLLM, :stream_text, fn _model, _message, %{stream: true} = _options ->
        {:ok, stream}
      end)

      processed_response = %{
        content: "The weather is sunny",
        conversation_id: "conv_stream",
        finished: true
      }

      expect(ToolResponseHandler, :process_streaming_response, fn ^stream,
                                                                  "conv_stream",
                                                                  _options ->
        {:ok, processed_response}
      end)

      options = %{stream: true}

      assert {:ok, response} =
               ToolIntegrationManager.generate_with_tools(
                 "What's the weather?",
                 [action],
                 options
               )

      assert response.content == "The weather is sunny"
    end
  end

  describe "tool choice parameter handling" do
    test "maps tool choice parameters correctly", %{weather_action: action} do
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      expect(ToolBuilder, :batch_convert, 4, fn _, _ -> {:ok, [tool_descriptor]} end)
      expect(ConversationManager, :create_conversation, 4, fn -> {:ok, "conv_choice"} end)

      # Test different tool choice options
      test_cases = [
        {:auto, "auto"},
        {:none, "none"},
        {:required, "required"},
        {{:function, "get_weather"}, %{type: "function", function: %{name: "get_weather"}}}
      ]

      Enum.each(test_cases, fn {input_choice, expected_output} ->
        expect(ReqLLM, :generate_text, fn _model, _message, options ->
          # Now it should be the input directly
          assert options.tool_choice == input_choice
          {:ok, %{content: "Response", usage: %{}}}
        end)

        expect(ToolResponseHandler, :process_llm_response, fn _response, _conv_id, _options ->
          {:ok, %{content: "Response", conversation_id: "conv_choice", finished: true}}
        end)

        options = %{tool_choice: input_choice}

        assert {:ok, _response} =
                 ToolIntegrationManager.generate_with_tools(
                   "Test message",
                   [action],
                   options
                 )
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles empty tool list gracefully" do
      expect(ToolBuilder, :batch_convert, fn [], _options ->
        {:ok, []}
      end)

      expect(ConversationManager, :create_conversation, fn ->
        {:ok, "conv_empty"}
      end)

      expect(ReqLLM, :generate_text, fn _model, _message, options ->
        assert options.tools == []
        {:ok, %{content: "Response without tools", usage: %{}}}
      end)

      expect(ToolResponseHandler, :process_llm_response, fn _response, _conv_id, _options ->
        {:ok, %{content: "Response without tools", conversation_id: "conv_empty", finished: true}}
      end)

      assert {:ok, response} =
               ToolIntegrationManager.generate_with_tools(
                 "Simple question",
                 []
               )

      assert response.content == "Response without tools"
    end

    test "handles response processing errors gracefully", %{weather_action: action} do
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      expect(ToolBuilder, :batch_convert, fn _, _ -> {:ok, [tool_descriptor]} end)
      expect(ConversationManager, :create_conversation, fn -> {:ok, "conv_error"} end)

      expect(ReqLLM, :generate_text, fn _, _, _ ->
        {:ok, %{content: "Response", usage: %{}}}
      end)

      expect(ToolResponseHandler, :process_llm_response, fn _response, _conv_id, _options ->
        {:error, "Processing failed"}
      end)

      assert {:error, "Processing failed"} =
               ToolIntegrationManager.generate_with_tools(
                 "Test",
                 [action]
               )
    end

    test "handles conversation creation failure", %{weather_action: action} do
      expect(ToolBuilder, :batch_convert, fn _, _ -> {:ok, []} end)

      expect(ConversationManager, :create_conversation, fn ->
        {:error, "Conversation creation failed"}
      end)

      assert {:error, "Conversation creation failed"} =
               ToolIntegrationManager.generate_with_tools("Test", [action])
    end
  end

  describe "concurrent usage" do
    test "handles multiple concurrent requests", %{weather_action: action} do
      tool_descriptor = %{name: "get_weather", callback: fn _ -> {:ok, %{}} end}

      # Setup mocks for concurrent requests
      expect(ToolBuilder, :batch_convert, 5, fn _, _ -> {:ok, [tool_descriptor]} end)

      expect(ConversationManager, :create_conversation, 5, fn ->
        conversation_id = "conv_#{:rand.uniform(10000)}"
        {:ok, conversation_id}
      end)

      expect(ReqLLM, :generate_text, 5, fn _model, _message, _options ->
        {:ok, %{content: "Concurrent response", usage: %{total_tokens: 25}}}
      end)

      expect(ToolResponseHandler, :process_llm_response, 5, fn _response, conv_id, _options ->
        {:ok, %{content: "Concurrent response", conversation_id: conv_id, finished: true}}
      end)

      # Execute concurrent requests
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            ToolIntegrationManager.generate_with_tools(
              "Concurrent request #{i}",
              [action]
            )
          end)
        end)

      results = Task.await_many(tasks, 5_000)

      # All should succeed
      assert length(results) == 5

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end
  end
end
