defmodule Jido.AI.ReqLlmBridge.ToolBuilderTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ReqLlmBridge.ToolBuilder

  @moduledoc """
  Tests for the ToolBuilder module.

  Tests cover:
  - Tool descriptor creation from Actions
  - Tool name and description extraction
  - Schema conversion from NimbleOptions to JSON Schema
  - Action validation and compatibility checking
  - Batch conversion of multiple Actions
  """

  # Helper module - Action with standard name/description
  defmodule StandardAction do
    use Jido.Action,
      name: "standard_action",
      description: "A standard test action",
      schema: [
        message: [type: :string, required: true, doc: "Test message"],
        count: [type: :integer, default: 1, doc: "Count value"]
      ]

    def run(params, _context) do
      {:ok, %{message: params[:message], count: params[:count]}}
    end
  end

  # Helper module - Action with generic name (will test underscored conversion)
  defmodule CustomNameAction do
    use Jido.Action,
      name: "custom_name",
      description: "Action with custom name",
      schema: [
        value: [type: :string, required: true]
      ]

    def run(params, _context) do
      {:ok, params}
    end
  end

  # Helper module - Action without description
  defmodule NoDescriptionAction do
    use Jido.Action,
      name: "no_description_action",
      schema: []

    def run(_params, _context) do
      {:ok, %{}}
    end
  end

  # Invalid module - not an Action
  defmodule NotAnAction do
    def some_function, do: :ok
  end

  # Invalid module - has metadata but no run/2
  defmodule NoRunFunction do
    def __action_metadata__, do: %{}
  end

  describe "3.1 Tool Descriptor Creation" do
    test "successful descriptor creation from valid Action" do
      # Use Jido.Actions.Basic.Sleep
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)

      # Verify required fields
      assert Map.has_key?(descriptor, :name)
      assert Map.has_key?(descriptor, :description)
      assert Map.has_key?(descriptor, :parameter_schema)
      assert Map.has_key?(descriptor, :callback)

      # Verify all fields are non-nil
      assert descriptor.name != nil
      assert descriptor.description != nil
      assert descriptor.parameter_schema != nil
      assert descriptor.callback != nil

      # Verify callback is a function
      assert is_function(descriptor.callback, 1)
    end

    test "successful descriptor creation with StandardAction" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction)

      assert descriptor.name == "standard_action"
      assert descriptor.description == "A standard test action"
      assert is_map(descriptor.parameter_schema)
      assert is_function(descriptor.callback, 1)
    end

    test "tool name extraction from Action with name/0" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction)
      assert descriptor.name == "standard_action"
    end

    test "tool name uses the name specified in Action definition" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(CustomNameAction)

      # Uses the name from the Action definition
      assert descriptor.name == "custom_name"
    end

    test "tool description extraction from Action with description/0" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction)
      assert descriptor.description == "A standard test action"
    end

    test "tool description extraction from Action without description/0" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(NoDescriptionAction)
      assert descriptor.description == "No description provided"
    end

    test "schema conversion from NimbleOptions to JSON Schema format" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction)

      # Verify schema is a map (JSON Schema structure)
      assert is_map(descriptor.parameter_schema)

      # Schema should have structure (exact format depends on SchemaValidator)
      # Basic check that conversion happened
      assert descriptor.parameter_schema != %{}
    end

    test "callback function can be executed" do
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction)

      # Execute callback with valid parameters
      params = %{"message" => "test", "count" => 5}
      assert {:ok, result} = descriptor.callback.(params)

      assert result.message == "test"
      assert result.count == 5
    end
  end

  describe "3.2 Action Validation" do
    test "validation succeeds for valid Action module" do
      # Jido.Actions.Basic.Sleep is a valid action
      assert :ok = ToolBuilder.validate_action_compatibility(Jido.Actions.Basic.Sleep)
    end

    test "validation succeeds for StandardAction" do
      assert :ok = ToolBuilder.validate_action_compatibility(StandardAction)
    end

    test "validation fails for non-existent module" do
      # Use a non-existent module atom
      assert {:error, error} = ToolBuilder.validate_action_compatibility(NonExistentModule)
      assert error.reason == "module_not_loaded"
    end

    test "validation fails for module without __action_metadata__/0" do
      # NotAnAction doesn't implement Jido.Action behavior
      assert {:error, error} = ToolBuilder.validate_action_compatibility(NotAnAction)
      assert error.reason == "invalid_action_module"
    end

    test "validation fails for module without run/2" do
      # NoRunFunction has __action_metadata__ but no run/2
      assert {:error, error} = ToolBuilder.validate_action_compatibility(NoRunFunction)
      assert error.reason == "missing_run_function"
    end

    test "create_tool_descriptor fails for invalid module" do
      # Attempting to create descriptor for invalid module
      assert {:error, error} = ToolBuilder.create_tool_descriptor(NotAnAction)
      assert error.reason == "tool_conversion_failed"
      assert Map.has_key?(error, :original_error)
    end
  end

  describe "3.3 Batch Conversion" do
    test "successful batch conversion of multiple Actions" do
      actions = [
        Jido.Actions.Basic.Sleep,
        StandardAction,
        CustomNameAction
      ]

      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions)

      # Should have 3 descriptors
      assert length(descriptors) == 3

      # All should be valid tool descriptors
      Enum.each(descriptors, fn descriptor ->
        assert Map.has_key?(descriptor, :name)
        assert Map.has_key?(descriptor, :description)
        assert Map.has_key?(descriptor, :parameter_schema)
        assert Map.has_key?(descriptor, :callback)
      end)
    end

    test "partial success when some Actions fail" do
      # Mix of valid and invalid actions
      actions = [
        StandardAction,
        NotAnAction,
        CustomNameAction
      ]

      # Should succeed with valid actions only
      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions)

      # Should have 2 descriptors (NotAnAction failed)
      assert length(descriptors) == 2

      # Verify we got the valid ones
      names = Enum.map(descriptors, & &1.name)
      assert "standard_action" in names
      assert "custom_name" in names
    end

    test "error when all conversions fail" do
      # All invalid actions
      actions = [
        NotAnAction,
        NoRunFunction,
        NonExistentModule
      ]

      assert {:error, error} = ToolBuilder.batch_convert(actions)
      assert error.reason == "all_conversions_failed"
      assert Map.has_key?(error, :failures)
      assert length(error.failures) == 3
    end

    test "batch conversion with empty list returns success with empty list" do
      assert {:ok, descriptors} = ToolBuilder.batch_convert([])
      assert descriptors == []
    end

    test "batch conversion preserves order of successful conversions" do
      actions = [StandardAction, CustomNameAction, NoDescriptionAction]

      assert {:ok, descriptors} = ToolBuilder.batch_convert(actions)
      assert length(descriptors) == 3

      # Verify order is preserved
      assert Enum.at(descriptors, 0).name == "standard_action"
      assert Enum.at(descriptors, 1).name == "custom_name"
      assert Enum.at(descriptors, 2).name == "no_description_action"
    end
  end

  describe "3.4 Conversion Options" do
    test "conversion with custom context" do
      opts = %{context: %{user_id: 123}}

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction, opts)
      assert is_function(descriptor.callback, 1)

      # Callback should work with custom context
      params = %{"message" => "test"}
      assert {:ok, _result} = descriptor.callback.(params)
    end

    test "conversion with custom timeout" do
      opts = %{timeout: 10_000}

      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction, opts)
      assert is_function(descriptor.callback, 1)
    end

    test "conversion with schema validation disabled" do
      opts = %{validate_schema: false}

      # Should still succeed even with validation disabled
      assert {:ok, descriptor} = ToolBuilder.create_tool_descriptor(StandardAction, opts)
      assert Map.has_key?(descriptor, :parameter_schema)
    end
  end
end
