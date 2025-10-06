defmodule Jido.AI.ReqLlmBridgeToolIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.ToolBuilder

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM.Tool)

    # Mock Action for integration testing
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
          ],
          include_forecast: [type: :boolean, default: false, doc: "Include 3-day forecast"]
        ]

      @impl true
      def run(params, _context) do
        # Simulate weather API call
        weather_data = %{
          location: params.location,
          temperature: if(params.units == :celsius, do: 22, else: 72),
          condition: "sunny",
          humidity: 65,
          units: params.units
        }

        forecast_data =
          if params.include_forecast do
            %{
              forecast: [
                %{day: "tomorrow", temperature: 24, condition: "cloudy"},
                %{day: "day_after", temperature: 26, condition: "sunny"}
              ]
            }
          else
            %{}
          end

        result = Map.merge(weather_data, forecast_data)
        {:ok, result}
      end
    end

    # Calculator Action for testing tool choice
    defmodule CalculatorAction do
      use Jido.Action,
        name: "calculator",
        description: "Performs basic arithmetic operations",
        schema: [
          operation: [
            type: {:in, [:add, :subtract, :multiply, :divide]},
            required: true,
            doc: "Operation type"
          ],
          a: [type: :float, required: true, doc: "First number"],
          b: [type: :float, required: true, doc: "Second number"]
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
          {:error, _} = error ->
            error

          value ->
            {:ok, %{result: value, operation: params.operation, inputs: [params.a, params.b]}}
        end
      end
    end

    {:ok,
     %{
       weather_action: WeatherAction,
       calculator_action: CalculatorAction
     }}
  end

  describe "end-to-end tool integration" do
    test "converts Action to ReqLLM tool and executes successfully", %{weather_action: action} do
      # Mock ReqLLM.tool/1 to simulate tool creation
      expect(ReqLLM.Tool, :tool, fn opts ->
        # Return a mock tool that we can test
        %{
          name: opts[:name],
          description: opts[:description],
          parameter_schema: opts[:parameter_schema],
          callback: opts[:callback]
        }
      end)

      # Convert Action to tool using the main API
      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Verify tool structure
      assert tool.name == "get_weather"
      assert tool.description == "Gets the current weather for a location"
      assert is_map(tool.parameter_schema)
      assert is_function(tool.callback, 1)

      # Test tool execution with various parameter formats
      params = %{
        "location" => "Paris",
        "units" => "fahrenheit",
        "include_forecast" => "true"
      }

      assert {:ok, result} = tool.callback.(params)
      assert result.location == "Paris"
      # Fahrenheit
      assert result.temperature == 72
      assert result.condition == "sunny"
      assert result.units == :fahrenheit
      assert Map.has_key?(result, :forecast)
    end

    test "handles tool choice parameters in request options", %{
      weather_action: weather,
      calculator_action: calc
    } do
      expect(ReqLLM.Tool, :tool, 2, fn opts ->
        %{name: opts[:name], callback: opts[:callback]}
      end)

      # Test various tool choice formats
      test_cases = [
        {:auto, "auto"},
        {"none", "none"},
        {:required, "required"},
        {{:function, "get_weather"}, %{type: "function", function: %{name: "get_weather"}}},
        {{:function, :calculator}, %{type: "function", function: %{name: "calculator"}}}
      ]

      Enum.each(test_cases, fn {input_choice, expected_output} ->
        params = %{
          temperature: 0.7,
          max_tokens: 150,
          tool_choice: input_choice,
          tools: [weather, calc]
        }

        options = ReqLlmBridge.build_req_llm_options(params)
        assert options.tool_choice == expected_output
      end)
    end

    test "batch converts multiple actions with mixed success", %{weather_action: valid} do
      # Create an invalid action
      defmodule InvalidAction do
        def name, do: "invalid"
        # Missing proper Action implementation
      end

      expect(ReqLLM.Tool, :tool, fn opts ->
        %{name: opts[:name], callback: opts[:callback]}
      end)

      actions = [valid, InvalidAction]

      # Should return successful conversions only
      assert {:ok, tools} = ReqLlmBridge.convert_tools(actions)
      assert length(tools) == 1
      assert hd(tools).name == "get_weather"
    end

    test "validates action compatibility before conversion", %{weather_action: action} do
      # Valid action should pass
      assert :ok = ReqLlmBridge.validate_tool_compatibility(action)

      # Invalid action should fail
      defmodule BrokenAction do
        def name, do: "broken"
      end

      assert {:error, error} = ReqLlmBridge.validate_tool_compatibility(BrokenAction)
      assert error.reason == "invalid_action_module"
    end
  end

  describe "tool execution error handling" do
    test "handles action execution errors gracefully", %{calculator_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Test division by zero
      params = %{
        "operation" => "divide",
        "a" => "10",
        "b" => "0"
      }

      assert {:error, error} = tool.callback.(params)
      assert error.type == "action_error"
    end

    test "handles parameter validation errors", %{weather_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Missing required parameter
      invalid_params = %{"units" => "celsius"}

      assert {:error, error} = tool.callback.(invalid_params)
      assert error.type == "parameter_validation_error"
    end

    test "handles type conversion errors", %{calculator_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Invalid number format
      params = %{
        "operation" => "add",
        "a" => "not_a_number",
        "b" => "5.5"
      }

      assert {:error, error} = tool.callback.(params)
      assert error.type == "parameter_validation_error"
    end

    test "handles timeout scenarios" do
      defmodule SlowAction do
        use Jido.Action,
          name: "slow_action",
          description: "An action that takes time",
          schema: [
            delay: [type: :integer, default: 100, doc: "Delay in milliseconds"]
          ]

        @impl true
        def run(%{delay: delay}, _context) do
          Process.sleep(delay)
          {:ok, %{completed: true}}
        end
      end

      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      # Create tool with custom timeout
      options = %{timeout: 50}
      assert {:ok, [tool]} = ReqLlmBridge.convert_tools_with_options([SlowAction], options)

      # Should timeout
      params = %{"delay" => "1000"}
      assert {:error, error} = tool.callback.(params)
      assert error.type == "execution_timeout"
    end
  end

  describe "advanced tool features" do
    test "supports complex parameter types", %{weather_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        # Verify schema conversion
        schema = opts[:parameter_schema]
        assert schema.type == "object"
        assert Map.has_key?(schema.properties, "location")
        assert Map.has_key?(schema.properties, "units")
        assert schema.properties["location"]["type"] == "string"
        assert schema.properties["units"]["type"] == "string"
        assert "location" in schema.required
        refute "units" in schema.required

        %{callback: opts[:callback], parameter_schema: schema}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Test with choice parameter
      params = %{
        "location" => "Tokyo",
        "units" => "celsius",
        "include_forecast" => "false"
      }

      assert {:ok, result} = tool.callback.(params)
      # Celsius
      assert result.temperature == 22
      refute Map.has_key?(result, :forecast)
    end

    test "handles default values correctly", %{weather_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([action])

      # Only provide required parameter
      params = %{"location" => "London"}

      assert {:ok, result} = tool.callback.(params)
      assert result.location == "London"
      # default value
      assert result.units == :celsius
      # default false
      refute Map.has_key?(result, :forecast)
    end

    test "supports tool execution with context", %{weather_action: action} do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      # Create tool with context
      context = %{user_id: 123, api_key: "test_key"}
      options = %{context: context}

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools_with_options([action], options)

      params = %{"location" => "Berlin"}
      assert {:ok, result} = tool.callback.(params)
      assert result.location == "Berlin"
    end
  end

  describe "backward compatibility" do
    test "maintains compatibility with existing tool consumers" do
      # Mock the legacy format expectations
      expect(ReqLLM.Tool, :tool, fn opts ->
        # Simulate ReqLLM.tool/1 return format
        %{
          name: opts[:name],
          description: opts[:description],
          parameter_schema: opts[:parameter_schema],
          callback: opts[:callback]
        }
      end)

      # Use the original API
      assert {:ok, tools} = ReqLlmBridge.convert_tools([WeatherAction])
      assert length(tools) == 1
      assert is_map(hd(tools))
    end

    test "preserves error format compatibility" do
      expect(ReqLLM.Tool, :tool, fn _opts ->
        raise "Simulated ReqLLM error"
      end)

      assert {:error, error} = ReqLlmBridge.convert_tools([WeatherAction])
      assert error.reason == "tool_conversion_error"
      assert Map.has_key?(error, :details)
      assert Map.has_key?(error, :original_error)
    end
  end

  describe "performance and scalability" do
    test "handles large number of tools efficiently" do
      # Create multiple actions
      actions =
        for i <- 1..20 do
          Module.create(
            :"TestAction#{i}",
            quote do
              use Jido.Action,
                name: unquote("test_action_#{i}"),
                description: unquote("Test action #{i}"),
                schema: [
                  value: [type: :integer, required: true, doc: unquote("Value #{i}")]
                ]

              @impl true
              def run(params, _context) do
                {:ok, %{value: params.value, action_id: unquote(i)}}
              end
            end,
            Elixir
          )
        end

      expect(ReqLLM.Tool, :tool, 20, fn opts ->
        %{name: opts[:name], callback: opts[:callback]}
      end)

      # Should convert all actions efficiently
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, tools} = ReqLlmBridge.convert_tools(actions)
      end_time = System.monotonic_time(:millisecond)

      assert length(tools) == 20
      # Should complete within 1 second
      assert end_time - start_time < 1000
    end

    test "handles concurrent tool execution safely" do
      expect(ReqLLM.Tool, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, [tool]} = ReqLlmBridge.convert_tools([WeatherAction])

      # Execute multiple concurrent requests
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            params = %{"location" => "City#{i}"}
            tool.callback.(params)
          end)
        end)

      results = Task.await_many(tasks, 5_000)

      # All should succeed
      assert length(results) == 10

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end
  end
end
