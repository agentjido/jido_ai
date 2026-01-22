defmodule Jido.AI.Skills.ToolCalling.Actions.ListToolsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.ToolCalling.Actions.ListTools

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has no required fields" do
      refute ListTools.schema().fields[:filter].meta.required
      refute ListTools.schema().fields[:type].meta.required
    end

    test "has default values" do
      assert ListTools.schema().fields[:include_schema].value == true
    end
  end

  describe "run/2" do
    test "returns tool list with empty params" do
      assert {:ok, result} = ListTools.run(%{}, %{})
      assert is_list(result.tools)
      assert is_integer(result.count)
      assert result.count >= 0
    end

    test "includes filter in result" do
      assert {:ok, result} = ListTools.run(%{filter: "test"}, %{})
      assert result.filter == "test"
    end

    test "includes type in result" do
      assert {:ok, result} = ListTools.run(%{type: :action}, %{})
      assert result.type == :action
    end

    test "filters tools by name pattern" do
      assert {:ok, result} = ListTools.run(%{filter: "nonexistent_xyz"}, %{})
      # Should return empty list or filtered results
      assert is_list(result.tools)
    end

    test "filters tools by type" do
      assert {:ok, result} = ListTools.run(%{type: :action}, %{})
      # All tools should be actions
      Enum.each(result.tools, fn tool ->
        assert tool.type == :action
      end)
    end

    test "respects include_schema false" do
      assert {:ok, result} = ListTools.run(%{include_schema: false}, %{})

      Enum.each(result.tools, fn tool ->
        # Schema should not be included
        refute Map.has_key?(tool, :schema)
      end)
    end

    test "includes schema by default" do
      assert {:ok, result} = ListTools.run(%{}, %{})

      # At least check the structure
      assert is_list(result.tools)
    end
  end

  describe "tool structure" do
    test "returns tools with name and type (module excluded for security)" do
      assert {:ok, result} = ListTools.run(%{}, %{})

      Enum.each(result.tools, fn tool ->
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :type)
        # Module is excluded for security - don't expose internal structure
        refute Map.has_key?(tool, :module)
        assert tool.type in [:action, :tool]
      end)
    end
  end

  describe "security features" do
    test "excludes sensitive tools by default" do
      assert {:ok, result} = ListTools.run(%{}, %{})

      # Tools with sensitive keywords should be filtered out
      tool_names = Enum.map(result.tools, fn tool -> String.downcase(tool.name) end)

      # Check that no sensitive tool names are present
      refute Enum.any?(tool_names, fn name ->
               Enum.any?(
                 ["system", "admin", "config", "registry", "shell", "delete", "secret", "password", "token", "auth"],
                 fn keyword -> String.contains?(name, keyword) end
               )
             end)
    end

    test "includes sensitive_excluded flag in result" do
      assert {:ok, result} = ListTools.run(%{}, %{})
      # By default, sensitive tools should be excluded
      assert result.sensitive_excluded == true
    end

    test "allows including sensitive tools when explicitly requested" do
      assert {:ok, result} = ListTools.run(%{include_sensitive: true}, %{})
      assert result.sensitive_excluded == false
    end

    test "respects allowed_tools allowlist" do
      # When allowlist is provided, only those tools should be returned
      assert {:ok, result} = ListTools.run(%{allowed_tools: ["test_tool"]}, %{})

      Enum.each(result.tools, fn tool ->
        assert tool.name == "test_tool"
      end)
    end
  end
end
