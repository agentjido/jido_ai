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
end
