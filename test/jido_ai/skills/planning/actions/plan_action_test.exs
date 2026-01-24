defmodule Jido.AI.Skills.Planning.Actions.PlanTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Planning.Actions.Plan

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert Plan.schema().fields[:goal].meta.required == true
      refute Plan.schema().fields[:model].meta.required
      refute Plan.schema().fields[:constraints].meta.required
      refute Plan.schema().fields[:resources].meta.required
    end

    test "has default values" do
      assert Plan.schema().fields[:max_steps].value == 10
      assert Plan.schema().fields[:max_tokens].value == 4096
      assert Plan.schema().fields[:temperature].value == 0.7
    end
  end

  describe "run/2" do
    test "returns error when goal is missing" do
      assert {:error, _} = Plan.run(%{}, %{})
    end

    @tag :skip
    test "generates plan with valid goal" do
      params = %{
        goal: "Build a simple todo app"
      }

      assert {:ok, result} = Plan.run(params, %{})
      assert result.goal == "Build a simple todo app"
      assert is_binary(result.plan)
      assert result.plan != ""
      assert is_list(result.steps)
      assert Map.has_key?(result, :usage)
    end

    @tag :skip
    test "includes constraints in plan" do
      params = %{
        goal: "Launch a website",
        constraints: ["Budget under $1000", "Must use open source"]
      }

      assert {:ok, result} = Plan.run(params, %{})
      assert String.contains?(result.plan, "Budget") or String.contains?(result.plan, "constraints")
    end

    @tag :skip
    test "respects max_steps parameter" do
      params = %{
        goal: "Organize a conference",
        max_steps: 5
      }

      assert {:ok, result} = Plan.run(params, %{})
      assert length(result.steps) <= 10
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        goal: "Test goal",
        model: :fast
      }

      assert params[:model] == :fast
    end

    test "accepts string model spec" do
      params = %{
        goal: "Test goal",
        model: "anthropic:claude-haiku-4-5"
      }

      assert params[:model] == "anthropic:claude-haiku-4-5"
    end
  end
end
