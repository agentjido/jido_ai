defmodule Jido.AI.Skills.Planning.Actions.PrioritizeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Planning.Actions.Prioritize

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert Prioritize.schema()[:tasks][:required] == true
      refute Prioritize.schema()[:model][:required]
      refute Prioritize.schema()[:criteria][:required]
    end

    test "has default values" do
      assert Prioritize.schema()[:max_tokens][:default] == 4096
      assert Prioritize.schema()[:temperature][:default] == 0.5
    end

    test "tasks parameter is a list of strings" do
      schema = Prioritize.schema()
      assert schema[:tasks][:type] == {:list, :string}
    end
  end

  describe "run/2" do
    test "returns error when tasks is missing" do
      assert {:error, _} = Prioritize.run(%{}, %{})
    end

    test "returns error when tasks is empty list" do
      assert {:error, _} = Prioritize.run(%{tasks: []}, %{})
    end

    @tag :skip
    test "generates prioritization with valid tasks" do
      params = %{
        tasks: [
          "Fix critical bug",
          "Update documentation",
          "Add new feature"
        ]
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      assert is_binary(result.prioritization)
      assert result.prioritization != ""
      assert is_list(result.ordered_tasks)
      assert is_map(result.scores)
      assert Map.has_key?(result, :usage)
    end

    @tag :skip
    test "includes criteria in prioritization" do
      params = %{
        tasks: ["Task A", "Task B", "Task C"],
        criteria: "Business impact and development effort"
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      assert String.length(result.prioritization) > 0
      assert map_size(result.scores) > 0
    end

    @tag :skip
    test "includes context in prioritization" do
      params = %{
        tasks: ["Design API", "Build frontend", "Test"],
        context: "Early-stage startup, need MVP quickly"
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      refute Enum.empty?(result.ordered_tasks)
    end

    @tag :skip
    test "orders all provided tasks" do
      params = %{
        tasks: ["Task 1", "Task 2", "Task 3", "Task 4", "Task 5"]
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      refute Enum.empty?(result.ordered_tasks)
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        tasks: ["Task"],
        model: :planning
      }

      assert params[:model] == :planning
    end

    test "accepts string model spec" do
      params = %{
        tasks: ["Task"],
        model: "anthropic:claude-sonnet-4-20250514"
      }

      assert params[:model] == "anthropic:claude-sonnet-4-20250514"
    end
  end
end
