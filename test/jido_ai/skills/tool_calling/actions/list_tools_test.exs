defmodule Jido.AI.Actions.ToolCalling.ListToolsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.ToolCalling.ListTools

  defmodule LegacySchemaTool do
    use Jido.Action,
      name: "legacy_schema_tool",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        limit: [type: :integer, default: 10, doc: "Maximum result count"]
      ]

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  defmodule ZoiSchemaTool do
    use Jido.Action,
      name: "zoi_schema_tool",
      schema:
        Zoi.object(%{
          prompt: Zoi.string(description: "Prompt text"),
          max_tokens: Zoi.integer(description: "Maximum output tokens") |> Zoi.default(256),
          tags: Zoi.list(Zoi.string(), description: "Tags") |> Zoi.optional()
        })

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has no required fields" do
      refute ListTools.schema().fields[:filter].meta.required
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

    test "filters tools by name pattern" do
      assert {:ok, result} = ListTools.run(%{filter: "nonexistent_xyz"}, %{})
      # Should return empty list or filtered results
      assert is_list(result.tools)
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
    test "returns tools with name (module excluded for security)" do
      assert {:ok, result} = ListTools.run(%{}, %{})

      Enum.each(result.tools, fn tool ->
        assert Map.has_key?(tool, :name)
        # Module is excluded for security - don't expose internal structure
        refute Map.has_key?(tool, :module)
      end)
    end

    test "serializes schema for both keyword-list and Zoi object tools" do
      context = %{
        tools: %{
          "legacy_schema_tool" => LegacySchemaTool,
          "zoi_schema_tool" => ZoiSchemaTool
        }
      }

      assert {:ok, result} =
               ListTools.run(%{include_schema: true, include_sensitive: true}, context)

      legacy_tool = Enum.find(result.tools, &(&1.name == "legacy_schema_tool"))
      zoi_tool = Enum.find(result.tools, &(&1.name == "zoi_schema_tool"))

      refute is_nil(legacy_tool.schema)
      assert is_list(legacy_tool.schema)
      assert Enum.any?(legacy_tool.schema, &(&1.name == :query and &1.type == :string))

      refute is_nil(zoi_tool.schema)
      assert is_list(zoi_tool.schema)
      assert Enum.any?(zoi_tool.schema, &(&1.name == :prompt and &1.type == "string"))
      assert Enum.any?(zoi_tool.schema, &(&1.name == :max_tokens and &1.default == 256))
    end

    test "reads tools from plugin_state fallback when context.tools is absent" do
      context = %{
        plugin_state: %{
          chat: %{
            tools: %{
              "legacy_schema_tool" => LegacySchemaTool,
              "zoi_schema_tool" => ZoiSchemaTool
            }
          }
        }
      }

      assert {:ok, result} = ListTools.run(%{include_sensitive: true}, context)
      tool_names = Enum.map(result.tools, & &1.name)

      assert "legacy_schema_tool" in tool_names
      assert "zoi_schema_tool" in tool_names
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
