defmodule Jido.AI.ReqLlmBridge.ToolBuilderTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.{SchemaValidator, ToolBuilder, ToolExecutor}

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)

    # Mock Action for testing
    defmodule TestAction do
      use Jido.Action,
        name: "test_action",
        description: "A test action for ReqLLM integration",
        schema: [
          name: [type: :string, required: true, doc: "The name parameter"],
          count: [type: :integer, default: 1, doc: "The count parameter"],
          enabled: [type: :boolean, default: false, doc: "Enable flag"]
        ]

      @impl true
      def run(params, _context) do
        {:ok,
         %{
           message: "Hello #{params.name}",
           count: params.count,
           enabled: params.enabled
         }}
      end
    end

    # Mock Action with complex schema
    defmodule ComplexAction do
      use Jido.Action,
        name: "complex_action",
        description: "An action with complex schema",
        schema: [
          items: [type: {:list, :string}, required: true, doc: "List of items"],
          config: [type: :map, doc: "Configuration map"],
          status: [type: {:in, [:active, :inactive]}, default: :inactive, doc: "Status choice"]
        ]

      @impl true
      def run(params, _context) do
        {:ok, %{processed: length(params.items), config: params.config, status: params.status}}
      end
    end

    # Invalid Action (missing required functions)
    defmodule InvalidAction do
      # This module doesn't implement the Jido.Action behavior properly
      def name, do: "invalid"
    end

    {:ok,
     %{
       test_action: TestAction,
       complex_action: ComplexAction,
       invalid_action: InvalidAction
     }}
  end

  describe "create_tool_descriptor/2" do
    test "successfully creates tool descriptor for valid action", %{test_action: action} do
      # Mock ReqLlmBridge.tool/1 to return a tool descriptor
      expect(ReqLLM, :tool, fn opts ->
        %{
          name: opts[:name],
          description: opts[:description],
          parameter_schema: opts[:parameter_schema],
          callback: opts[:callback]
        }
      end)

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(action)
      assert descriptor.name == "test_action"
      assert descriptor.description == "A test action for ReqLLM integration"
      assert is_map(descriptor.parameter_schema)
      assert is_function(descriptor.callback, 1)
    end

    test "creates tool descriptor with custom options", %{test_action: action} do
      expect(ReqLLM, :tool, fn _opts ->
        %{
          name: "test_action",
          description: "test",
          parameter_schema: %{},
          callback: fn _ -> :ok end
        }
      end)

      options = %{
        context: %{user_id: 123},
        timeout: 10_000,
        validate_schema: false
      }

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(action, options)
      assert is_map(descriptor)
    end

    test "validates action module before conversion", %{invalid_action: invalid} do
      result = ToolBuilder.create_tool_descriptor(invalid)

      assert {:error, error} = result
      assert error.reason == "tool_conversion_failed"
      assert error.action_module == invalid
    end

    test "handles schema conversion failures gracefully", %{test_action: action} do
      # Mock SchemaValidator to fail
      expect(ReqLLM, :tool, fn _opts -> raise "Schema conversion failed" end)

      assert {:error, error} = ToolBuilder.create_tool_descriptor(action)
      assert error.reason == "conversion_exception"
      assert String.contains?(error.details, "Schema conversion failed")
    end

    test "creates callback function that executes action correctly", %{test_action: action} do
      expect(ReqLLM, :tool, fn opts ->
        # Return the callback so we can test it
        %{callback: opts[:callback]}
      end)

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(action)
      callback = descriptor.callback

      # Test the callback execution
      params = %{"name" => "Pascal", "count" => "5", "enabled" => "true"}

      assert {:ok, result} = callback.(params)
      assert result.message == "Hello Pascal"
      assert result.count == 5
      assert result.enabled == true
    end

    test "callback handles parameter validation errors", %{test_action: action} do
      expect(ReqLLM, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(action)
      callback = descriptor.callback

      # Test with invalid parameters (missing required field)
      invalid_params = %{"count" => "5"}

      assert {:error, error} = callback.(invalid_params)
      assert error.type == "parameter_validation_error"
    end
  end

  describe "batch_convert/2" do
    test "converts multiple actions successfully", %{
      test_action: action1,
      complex_action: action2
    } do
      expect(ReqLLM, :tool, 2, fn opts ->
        %{
          name: opts[:name],
          description: opts[:description],
          parameter_schema: opts[:parameter_schema],
          callback: opts[:callback]
        }
      end)

      actions = [action1, action2]
      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions)
      assert length(descriptors) == 2

      names = Enum.map(descriptors, & &1.name)
      assert "test_action" in names
      assert "complex_action" in names
    end

    test "returns successful conversions even when some fail", %{
      test_action: valid,
      invalid_action: invalid
    } do
      expect(ReqLLM, :tool, fn opts ->
        %{
          name: opts[:name],
          description: opts[:description],
          parameter_schema: opts[:parameter_schema],
          callback: opts[:callback]
        }
      end)

      actions = [valid, invalid]
      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions)
      assert length(descriptors) == 1
      assert hd(descriptors).name == "test_action"
    end

    test "returns error when no conversions succeed", %{invalid_action: invalid} do
      actions = [invalid]
      assert {:error, error} = ToolBuilder.batch_convert(actions)
      assert error.reason == "all_conversions_failed"
      assert is_list(error.failures)
    end

    test "applies options to all conversions", %{test_action: action} do
      expect(ReqLLM, :tool, fn _opts ->
        %{name: "test", description: "test", parameter_schema: %{}, callback: fn _ -> :ok end}
      end)

      options = %{context: %{user_id: 123}}
      actions = [action]

      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions, options)
      assert length(descriptors) == 1
    end
  end

  describe "validate_action_compatibility/1" do
    test "validates compatible action", %{test_action: action} do
      assert :ok = ToolBuilder.validate_action_compatibility(action)
    end

    test "rejects invalid action module", %{invalid_action: invalid} do
      assert {:error, error} = ToolBuilder.validate_action_compatibility(invalid)
      assert error.reason == "invalid_action_module"
    end

    test "rejects non-existent module" do
      assert {:error, error} = ToolBuilder.validate_action_compatibility(NonExistentModule)
      assert error.reason == "module_not_loaded"
    end

    test "validates complex schema compatibility", %{complex_action: action} do
      assert :ok = ToolBuilder.validate_action_compatibility(action)
    end
  end

  describe "error handling and edge cases" do
    test "handles action that raises exception during run", %{test_action: _action} do
      defmodule FailingAction do
        use Jido.Action,
          name: "failing_action",
          description: "An action that always fails",
          schema: []

        @impl true
        def run(_params, _context) do
          raise "Simulated failure"
        end
      end

      expect(ReqLLM, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(FailingAction)
      callback = descriptor.callback

      assert {:error, error} = callback.(%{})
      assert error.type == "exception"
    end

    test "handles action with non-serializable result", %{test_action: _action} do
      defmodule NonSerializableAction do
        use Jido.Action,
          name: "non_serializable",
          description: "Returns non-serializable data",
          schema: []

        @impl true
        def run(_params, _context) do
          {:ok, %{pid: self(), ref: make_ref()}}
        end
      end

      expect(ReqLLM, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(NonSerializableAction)
      callback = descriptor.callback

      # Should handle serialization issues gracefully
      assert {:ok, result} = callback.(%{})
      assert is_map(result)
      # Should either sanitize or provide fallback
      assert Map.has_key?(result, :pid) or Map.has_key?(result, :serialization_fallback)
    end

    test "handles timeout during action execution" do
      defmodule SlowAction do
        use Jido.Action,
          name: "slow_action",
          description: "An action that takes too long",
          schema: []

        @impl true
        def run(_params, _context) do
          # Simulate slow operation
          # Longer than default timeout
          Process.sleep(6000)
          {:ok, %{completed: true}}
        end
      end

      expect(ReqLLM, :tool, fn opts ->
        %{callback: opts[:callback]}
      end)

      # Create tool with short timeout
      options = %{timeout: 100}
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(SlowAction, options)
      callback = descriptor.callback

      assert {:error, error} = callback.(%{})
      assert error.type == "execution_timeout"
    end
  end

  describe "schema validation and conversion" do
    test "converts simple schema correctly", %{test_action: action} do
      expect(ReqLLM, :tool, fn opts ->
        schema = opts[:parameter_schema]
        assert schema.type == "object"
        assert Map.has_key?(schema.properties, "name")
        assert Map.has_key?(schema.properties, "count")
        assert "name" in schema.required

        %{parameter_schema: schema}
      end)

      assert {:ok, _descriptor} = ToolBuilder.create_tool_descriptor(action)
    end

    test "converts complex schema with lists and choices", %{complex_action: action} do
      expect(ReqLLM, :tool, fn opts ->
        schema = opts[:parameter_schema]
        assert schema.type == "object"
        assert Map.has_key?(schema.properties, "items")
        assert schema.properties["items"]["type"] == "array"
        assert Map.has_key?(schema.properties, "status")

        %{parameter_schema: schema}
      end)

      assert {:ok, _descriptor} = ToolBuilder.create_tool_descriptor(action)
    end
  end

  describe "logging and debugging" do
    test "logs conversion success when logging enabled" do
      # Enable logging for this test
      Application.put_env(:jido_ai, :enable_req_llm_logging, true)

      expect(ReqLLM, :tool, fn _opts ->
        %{name: "test", description: "test", parameter_schema: %{}, callback: fn _ -> :ok end}
      end)

      options = %{enable_logging: true}

      # Should not raise any errors and should complete successfully
      assert {:ok, _descriptor} = ToolBuilder.create_tool_descriptor(TestAction, options)

      # Cleanup
      Application.put_env(:jido_ai, :enable_req_llm_logging, false)
    end
  end
end
