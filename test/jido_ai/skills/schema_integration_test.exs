defmodule Jido.AI.Plugins.SchemaIntegrationTest do
  @moduledoc """
  Integration tests validating schema availability for public plugins and actions.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Chat, as: ChatPlugin
  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}
  alias Jido.AI.Plugins.Reasoning.{Adaptive, AlgorithmOfThoughts, ChainOfThought, GraphOfThoughts, TRM, TreeOfThoughts}
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  require Jido.AI.Plugins.Chat
  require Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  require Jido.AI.Plugins.Planning
  require Jido.AI.Actions.Planning.{Plan, Decompose, Prioritize}
  require Jido.AI.Plugins.Reasoning.Adaptive
  require Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts
  require Jido.AI.Plugins.Reasoning.ChainOfThought
  require Jido.AI.Plugins.Reasoning.GraphOfThoughts
  require Jido.AI.Plugins.Reasoning.TRM
  require Jido.AI.Plugins.Reasoning.TreeOfThoughts
  require Jido.AI.Actions.Reasoning.RunStrategy
  require Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  describe "LLM and Tool-Calling Action Schemas" do
    test "Chat action has schema function" do
      assert function_exported?(Chat, :schema, 0)
    end

    test "Complete action has schema function" do
      assert function_exported?(Complete, :schema, 0)
    end

    test "Embed action has schema function" do
      assert function_exported?(Embed, :schema, 0)
    end

    test "GenerateObject action has schema function" do
      assert function_exported?(GenerateObject, :schema, 0)
    end

    test "CallWithTools action has schema function" do
      assert function_exported?(CallWithTools, :schema, 0)
    end

    test "ExecuteTool action has schema function" do
      assert function_exported?(ExecuteTool, :schema, 0)
    end

    test "ListTools action has schema function" do
      assert function_exported?(ListTools, :schema, 0)
    end
  end

  describe "Planning and Reasoning Action Schemas" do
    test "Plan action has schema function" do
      assert function_exported?(Plan, :schema, 0)
    end

    test "Decompose action has schema function" do
      assert function_exported?(Decompose, :schema, 0)
    end

    test "Prioritize action has schema function" do
      assert function_exported?(Prioritize, :schema, 0)
    end

    test "RunStrategy action has schema function" do
      assert function_exported?(RunStrategy, :schema, 0)
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
        RunStrategy
      ]

      for action <- actions do
        schema = action.schema()

        assert is_map(schema) or is_struct(schema),
               "#{inspect(action)} schema should return a map-like structure"
      end
    end
  end

  describe "Plugin Action Schema Coverage" do
    test "Chat plugin actions all expose schema/0" do
      actions = ChatPlugin.actions()
      assert length(actions) == 7

      for action <- actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "Planning plugin actions all expose schema/0" do
      actions = Planning.actions()
      assert length(actions) == 3

      for action <- actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "strategy plugins expose RunStrategy action" do
      plugins = [ChainOfThought, AlgorithmOfThoughts, TreeOfThoughts, GraphOfThoughts, TRM, Adaptive]

      for plugin <- plugins do
        assert plugin.actions() == [RunStrategy]
      end
    end

    test "total unique action count across public plugins" do
      all_actions =
        ChatPlugin.actions() ++
          Planning.actions() ++
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
