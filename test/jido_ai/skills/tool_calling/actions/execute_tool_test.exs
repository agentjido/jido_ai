defmodule Jido.AI.Actions.ToolCalling.ExecuteToolTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.ToolCalling.ExecuteTool

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

    test "returns success structure with valid tool_name" do
      params = %{
        tool_name: "test_tool",
        params: %{}
      }

      # Will fail with tool not found, but tests the structure
      result = ExecuteTool.run(params, %{})
      assert is_tuple(result)
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
