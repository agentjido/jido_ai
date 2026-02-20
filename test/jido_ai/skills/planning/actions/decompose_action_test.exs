defmodule Jido.AI.Actions.Planning.DecomposeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Planning.Decompose
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "has required fields" do
      assert Decompose.schema().fields[:goal].meta.required == true
      refute Decompose.schema().fields[:model].meta.required
      refute Decompose.schema().fields[:context].meta.required
    end

    test "has default values" do
      assert Decompose.schema().fields[:max_depth].value == 3
      assert Decompose.schema().fields[:max_tokens].value == 4096
      assert Decompose.schema().fields[:temperature].value == 0.6
    end
  end

  describe "run/2" do
    test "returns error when goal is missing" do
      assert {:error, _} = Decompose.run(%{}, %{})
    end

    test "generates decomposition with valid goal" do
      params = %{
        goal: "Build a mobile application"
      }

      assert {:ok, result} = Decompose.run(params, %{})
      assert result.goal == "Build a mobile application"
      assert is_binary(result.decomposition)
      assert result.decomposition != ""
      assert is_list(result.sub_goals)
      assert result.depth == 3
      assert Map.has_key?(result, :usage)
    end

    test "includes context in decomposition" do
      params = %{
        goal: "Organize an event",
        context: "Tech conference for developers, limited budget"
      }

      assert {:ok, result} = Decompose.run(params, %{})
      assert String.length(result.decomposition) > 0
    end

    test "respects max_depth parameter" do
      params = %{
        goal: "Start a business",
        max_depth: 2
      }

      assert {:ok, result} = Decompose.run(params, %{})
      assert result.depth == 2
    end

    test "clamps max_depth to reasonable range" do
      params = %{
        goal: "Test goal",
        max_depth: 10
      }

      assert {:ok, result} = Decompose.run(params, %{})
      assert result.depth <= 5
    end

    test "uses plugin defaults when params are omitted" do
      params = %{goal: "Break down roadmap"}

      context = %{
        provided_params: [:goal],
        plugin_state: %{planning: %{default_model: :fast, default_max_tokens: 2222, default_temperature: 0.2}}
      }

      assert {:ok, result} = Decompose.run(params, context)
      assert result.model == Jido.AI.resolve_model(:fast)
    end

    test "explicit model overrides plugin default" do
      params = %{goal: "Break down roadmap", model: "custom:model"}

      context = %{
        provided_params: [:goal, :model],
        plugin_state: %{planning: %{default_model: :fast}}
      }

      assert {:ok, result} = Decompose.run(params, context)
      assert result.model == "custom:model"
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        goal: "Test goal",
        model: :planning
      }

      assert params[:model] == :planning
    end

    test "accepts string model spec" do
      params = %{
        goal: "Test goal",
        model: "anthropic:claude-sonnet-4-20250514"
      }

      assert params[:model] == "anthropic:claude-sonnet-4-20250514"
    end
  end
end
