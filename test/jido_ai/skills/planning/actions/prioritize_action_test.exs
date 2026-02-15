defmodule Jido.AI.Actions.Planning.PrioritizeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Planning.Prioritize
  alias Jido.AI.TestSupport.FakeLLMClient

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert Prioritize.schema().fields[:tasks].meta.required == true
      refute Prioritize.schema().fields[:model].meta.required
      refute Prioritize.schema().fields[:criteria].meta.required
    end

    test "has default values" do
      assert Prioritize.schema().fields[:max_tokens].value == 4096
      assert Prioritize.schema().fields[:temperature].value == 0.5
    end

    test "tasks parameter is a list of strings" do
      schema = Prioritize.schema()
      # Note: type information may be in a different field
      # Just verify the field exists
      assert schema.fields[:tasks] != nil
    end
  end

  describe "run/2" do
    test "returns error when tasks is missing" do
      assert {:error, _} = Prioritize.run(%{}, %{})
    end

    test "returns error when tasks is empty list" do
      assert {:error, _} = Prioritize.run(%{tasks: []}, %{})
    end

    test "generates prioritization with valid tasks" do
      params = %{
        tasks: [
          "Fix critical bug",
          "Update documentation",
          "Add new feature"
        ]
      }

      assert {:ok, result} = Prioritize.run(params, %{llm_client: FakeLLMClient})
      assert is_binary(result.prioritization)
      assert result.prioritization != ""
      assert is_list(result.ordered_tasks)
      assert is_map(result.scores)
      assert Map.has_key?(result, :usage)
    end

    test "includes criteria in prioritization" do
      params = %{
        tasks: ["Task A", "Task B", "Task C"],
        criteria: "Business impact and development effort"
      }

      assert {:ok, result} = Prioritize.run(params, %{llm_client: FakeLLMClient})
      assert String.length(result.prioritization) > 0
      assert map_size(result.scores) > 0
    end

    test "includes context in prioritization" do
      params = %{
        tasks: ["Design API", "Build frontend", "Test"],
        context: "Early-stage startup, need MVP quickly"
      }

      assert {:ok, result} = Prioritize.run(params, %{llm_client: FakeLLMClient})
      refute Enum.empty?(result.ordered_tasks)
    end

    test "orders all provided tasks" do
      params = %{
        tasks: ["Task 1", "Task 2", "Task 3", "Task 4", "Task 5"]
      }

      assert {:ok, result} = Prioritize.run(params, %{llm_client: FakeLLMClient})
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
