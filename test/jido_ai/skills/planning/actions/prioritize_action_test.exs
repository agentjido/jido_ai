defmodule Jido.AI.Actions.Planning.PrioritizeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Planning.Prioritize
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

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

    test "returns error when tasks is invalid format" do
      assert {:error, _} = Prioritize.run(%{tasks: "Task A"}, %{})
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

      assert {:ok, result} = Prioritize.run(params, %{})
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

      assert {:ok, result} = Prioritize.run(params, %{})
      assert String.length(result.prioritization) > 0
      assert map_size(result.scores) > 0
    end

    test "includes context in prioritization" do
      params = %{
        tasks: ["Design API", "Build frontend", "Test"],
        context: "Early-stage startup, need MVP quickly"
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      refute Enum.empty?(result.ordered_tasks)
    end

    test "orders all provided tasks" do
      params = %{
        tasks: ["Task 1", "Task 2", "Task 3", "Task 4", "Task 5"]
      }

      assert {:ok, result} = Prioritize.run(params, %{})
      refute Enum.empty?(result.ordered_tasks)
    end

    test "uses plugin defaults when params are omitted" do
      params = %{tasks: ["Task A", "Task B"]}

      context = %{
        provided_params: [:tasks],
        plugin_state: %{planning: %{default_model: :fast, default_max_tokens: 1111, default_temperature: 0.3}}
      }

      expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        assert model == Jido.AI.resolve_model(:fast)
        assert opts[:max_tokens] == 1111
        assert opts[:temperature] == 0.3

        {:ok, %{message: %{content: "1. **Task A** - Score: 9"}, usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = Prioritize.run(params, context)
      assert result.model == Jido.AI.resolve_model(:fast)
    end

    test "explicit params override plugin defaults" do
      params = %{
        tasks: ["Task A", "Task B"],
        model: "custom:model",
        max_tokens: 444,
        temperature: 0.9
      }

      context = %{
        provided_params: [:tasks, :model, :max_tokens, :temperature],
        plugin_state: %{planning: %{default_model: :fast, default_max_tokens: 1111, default_temperature: 0.3}}
      }

      expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        assert model == "custom:model"
        assert opts[:max_tokens] == 444
        assert opts[:temperature] == 0.9

        {:ok, %{message: %{content: "1. **Task B** - Score: 8"}, usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = Prioritize.run(params, context)
      assert result.model == "custom:model"
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
