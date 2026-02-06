defmodule Jido.AI.ToolAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ToolAdapter

  # Test action with empty schema
  defmodule EmptySchemaAction do
    use Jido.Action,
      name: "empty_action",
      description: "An action with no parameters",
      schema: []
  end

  # Test action with parameters
  defmodule ParamAction do
    use Jido.Action,
      name: "param_action",
      description: "An action with parameters",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        limit: [type: :integer, default: 10, doc: "Max results"]
      ]
  end

  describe "from_action/2" do
    test "converts action to ReqLLM.Tool struct" do
      tool = ToolAdapter.from_action(ParamAction)

      assert %ReqLLM.Tool{} = tool
      assert tool.name == "param_action"
      assert tool.description == "An action with parameters"
      assert is_map(tool.parameter_schema)
    end

    test "applies prefix to tool name" do
      tool = ToolAdapter.from_action(ParamAction, prefix: "myapp_")

      assert tool.name == "myapp_param_action"
    end

    test "handles empty schema with valid JSON schema output" do
      tool = ToolAdapter.from_action(EmptySchemaAction)

      assert %ReqLLM.Tool{} = tool
      assert tool.name == "empty_action"
      # Key assertion: empty schema must produce valid object schema with required array
      assert tool.parameter_schema == %{"type" => "object", "properties" => %{}, "required" => []}
    end
  end

  describe "from_actions/2" do
    test "converts list of actions to tools" do
      tools = ToolAdapter.from_actions([EmptySchemaAction, ParamAction])

      assert length(tools) == 2
      assert Enum.all?(tools, &match?(%ReqLLM.Tool{}, &1))
    end

    test "applies filter function" do
      tools =
        ToolAdapter.from_actions(
          [EmptySchemaAction, ParamAction],
          filter: fn mod -> mod.name() == "param_action" end
        )

      assert length(tools) == 1
      assert hd(tools).name == "param_action"
    end

    test "applies prefix to all tools" do
      tools = ToolAdapter.from_actions([EmptySchemaAction, ParamAction], prefix: "v2_")

      assert Enum.all?(tools, fn tool -> String.starts_with?(tool.name, "v2_") end)
    end
  end

  describe "lookup_action/2" do
    test "finds action by tool name" do
      assert {:ok, ParamAction} = ToolAdapter.lookup_action("param_action", [EmptySchemaAction, ParamAction])
    end

    test "returns error for unknown tool" do
      assert {:error, :not_found} = ToolAdapter.lookup_action("unknown", [ParamAction])
    end
  end

  describe "lookup_action/3 with prefix" do
    test "finds action by prefixed tool name" do
      assert {:ok, ParamAction} =
               ToolAdapter.lookup_action("myapp_param_action", [EmptySchemaAction, ParamAction], prefix: "myapp_")
    end

    test "returns error when prefix doesn't match" do
      assert {:error, :not_found} =
               ToolAdapter.lookup_action("param_action", [ParamAction], prefix: "myapp_")
    end

    test "returns error for unknown prefixed tool" do
      assert {:error, :not_found} =
               ToolAdapter.lookup_action("myapp_unknown", [ParamAction], prefix: "myapp_")
    end
  end

  describe "validate_actions/1" do
    defmodule NotAnAction do
      def some_function, do: :ok
    end

    test "returns :ok for valid action modules" do
      assert :ok = ToolAdapter.validate_actions([EmptySchemaAction, ParamAction])
    end

    test "returns error for invalid action module" do
      assert {:error, {:invalid_action, NotAnAction, _reason}} =
               ToolAdapter.validate_actions([ParamAction, NotAnAction])
    end
  end

  describe "duplicate detection" do
    defmodule DuplicateNameAction do
      use Jido.Action,
        name: "param_action",
        description: "Same name as ParamAction",
        schema: []
    end

    test "from_actions raises on duplicate tool names" do
      assert_raise ArgumentError, ~r/duplicate tool names/i, fn ->
        ToolAdapter.from_actions([ParamAction, DuplicateNameAction])
      end
    end

    test "from_actions raises on duplicate names after prefix" do
      defmodule AAction do
        use Jido.Action,
          name: "action",
          description: "First action",
          schema: []
      end

      defmodule BAction do
        use Jido.Action,
          name: "action",
          description: "Second action with same name",
          schema: []
      end

      assert_raise ArgumentError, ~r/duplicate tool names/i, fn ->
        ToolAdapter.from_actions([AAction, BAction], prefix: "test_")
      end
    end
  end
end
