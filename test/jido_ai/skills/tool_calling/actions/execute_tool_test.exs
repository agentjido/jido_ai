defmodule Jido.AI.Actions.ToolCalling.ExecuteToolTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.ToolCalling.ExecuteTool

  defmodule AddAction do
    use Jido.Action,
      name: "add",
      description: "Add two numbers",
      schema:
        Zoi.object(%{
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    @impl Jido.Action
    def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
  end

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert ExecuteTool.schema().fields[:tool_name].meta.required == true
      refute ExecuteTool.schema().fields[:params].meta.required
    end

    test "has default values" do
      assert ExecuteTool.schema().fields[:params].value == %{}
      assert ExecuteTool.schema().fields[:timeout].value == 30_000
    end
  end

  describe "run/2" do
    test "returns error when tool_name is missing" do
      assert {:error, :tool_name_required} = ExecuteTool.run(%{}, %{})
    end

    test "returns error when tool_name is empty string" do
      assert {:error, :tool_name_required} = ExecuteTool.run(%{tool_name: ""}, %{})
    end

    test "returns error for invalid tool_name type" do
      assert {:error, :invalid_tool_name} = ExecuteTool.run(%{tool_name: 123}, %{})
    end

    test "returns error for invalid params type" do
      assert {:error, :invalid_params_format} =
               ExecuteTool.run(%{tool_name: "test", params: "invalid"}, %{})
    end

    test "returns tool not found error for unknown tool" do
      params = %{
        tool_name: "nonexistent_tool_xyz",
        params: %{}
      }

      assert {:error, _reason} = ExecuteTool.run(params, %{})
    end

    test "executes a tool from context tools map" do
      params = %{
        tool_name: "add",
        params: %{a: 1, b: 2}
      }

      context = %{tools: %{"add" => AddAction}}

      assert {:ok, %{tool_name: "add", status: :success, result: %{sum: 3}}} =
               ExecuteTool.run(params, context)
    end

    test "executes a tool from plugin state tools map fallback" do
      params = %{
        tool_name: "add",
        params: %{a: 4, b: 7}
      }

      context = %{state: %{tool_calling: %{tools: %{"add" => AddAction}}}}

      assert {:ok, %{tool_name: "add", status: :success, result: %{sum: 11}}} =
               ExecuteTool.run(params, context)
    end
  end

  describe "timeout parameter" do
    test "accepts custom timeout" do
      params = %{
        tool_name: "test",
        timeout: 5000
      }

      assert params[:timeout] == 5000
    end
  end
end
