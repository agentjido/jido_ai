defmodule Jido.AI.Plugins.SchemaIntegrationTest do
  @moduledoc """
  Integration tests validating schema availability for public plugins and actions.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Chat, as: ChatPlugin
  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}

  alias Jido.AI.Plugins.Reasoning.{
    Adaptive,
    AlgorithmOfThoughts,
    ChainOfDraft,
    ChainOfThought,
    GraphOfThoughts,
    TRM,
    TreeOfThoughts
  }

  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  defp assert_schema(action) do
    Code.ensure_loaded!(action)
    assert function_exported?(action, :schema, 0)
  end

  describe "LLM and Tool-Calling Action Schemas" do
    test "Chat action has schema function" do
      assert_schema(Chat)
    end

    test "Complete action has schema function" do
      assert_schema(Complete)
    end

    test "Embed action has schema function" do
      assert_schema(Embed)
    end

    test "GenerateObject action has schema function" do
      assert_schema(GenerateObject)
    end

    test "CallWithTools action has schema function" do
      assert_schema(CallWithTools)
    end

    test "ExecuteTool action has schema function" do
      assert_schema(ExecuteTool)
    end

    test "ListTools action has schema function" do
      assert_schema(ListTools)
    end
  end

  describe "Planning and Reasoning Action Schemas" do
    test "Plan action has schema function" do
      assert_schema(Plan)
    end

    test "Decompose action has schema function" do
      assert_schema(Decompose)
    end

    test "Prioritize action has schema function" do
      assert_schema(Prioritize)
    end

    test "RunStrategy action has schema function" do
      assert_schema(RunStrategy)
    end
  end

  describe "Skill Action Schemas" do
    test "LoadSkill action has schema function" do
      assert_schema(LoadSkill)
    end

    test "LoadResource action has schema function" do
      assert_schema(LoadResource)
    end
  end

  describe "Schema Structure" do
    test "all core action schemas return map-like structures" do
      actions = [
        Chat,
        Complete,
        Embed,
        GenerateObject,
        Plan,
        Decompose,
        Prioritize,
        CallWithTools,
        ExecuteTool,
        ListTools,
        LoadSkill,
        LoadResource,
        RunStrategy
      ]

      for action <- actions do
        schema = action.schema()

        assert is_map(schema),
               "#{inspect(action)} schema should return a map-like structure"
      end
    end
  end

  describe "Plugin Action Schema Coverage" do
    test "Chat plugin actions all expose schema/0" do
      actions = ChatPlugin.actions()
      assert length(actions) == 7

      for action <- actions do
        assert_schema(action)
      end
    end

    test "Planning plugin actions all expose schema/0" do
      actions = Planning.actions()
      assert length(actions) == 3

      for action <- actions do
        assert_schema(action)
      end
    end

    test "strategy plugins expose RunStrategy action" do
      plugins = [ChainOfDraft, ChainOfThought, AlgorithmOfThoughts, TreeOfThoughts, GraphOfThoughts, TRM, Adaptive]

      for plugin <- plugins do
        assert plugin.actions() == [RunStrategy]
      end
    end

    test "total unique action count across public plugins" do
      all_actions =
        ChatPlugin.actions() ++
          Planning.actions() ++
          ChainOfDraft.actions() ++
          ChainOfThought.actions() ++
          AlgorithmOfThoughts.actions() ++
          TreeOfThoughts.actions() ++
          GraphOfThoughts.actions() ++
          TRM.actions() ++
          Adaptive.actions()

      assert length(Enum.uniq(all_actions)) == 11
    end
  end
end
