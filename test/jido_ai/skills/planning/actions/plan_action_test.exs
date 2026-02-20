defmodule Jido.AI.Actions.Planning.PlanTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Planning.Plan
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

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

    test "returns error when goal is empty string" do
      assert {:error, _} = Plan.run(%{goal: ""}, %{})
    end

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

    test "includes constraints in plan" do
      params = %{
        goal: "Launch a website",
        constraints: ["Budget under $1000", "Must use open source"]
      }

      assert {:ok, result} = Plan.run(params, %{})
      assert result.goal == "Launch a website"
      assert String.length(result.plan) > 0
      refute Enum.empty?(result.steps)
    end

    test "respects max_steps parameter" do
      params = %{
        goal: "Organize a conference",
        max_steps: 5
      }

      assert {:ok, result} = Plan.run(params, %{})
      assert length(result.steps) <= 10
    end

    test "uses plugin defaults when params are omitted" do
      params = %{goal: "Ship a release"}

      context = %{
        provided_params: [:goal],
        plugin_state: %{planning: %{default_model: :fast, default_max_tokens: 3333, default_temperature: 0.1}},
        default_max_steps: 6
      }

      expect(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == Jido.AI.resolve_model(:fast)
        assert opts[:max_tokens] == 3333
        assert opts[:temperature] == 0.1
        assert latest_user_prompt(messages) =~ "approximately 6 steps"

        {:ok, %{message: %{content: "1. **Scope**"}, usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = Plan.run(params, context)
      assert result.model == Jido.AI.resolve_model(:fast)
    end

    test "explicit params override plugin defaults" do
      params = %{
        goal: "Ship a release",
        model: "custom:model",
        max_steps: 4,
        max_tokens: 555,
        temperature: 0.4
      }

      context = %{
        provided_params: [:goal, :model, :max_steps, :max_tokens, :temperature],
        plugin_state: %{planning: %{default_model: :fast, default_max_tokens: 3333, default_temperature: 0.1}},
        default_max_steps: 9
      }

      expect(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == "custom:model"
        assert opts[:max_tokens] == 555
        assert opts[:temperature] == 0.4
        assert latest_user_prompt(messages) =~ "approximately 4 steps"

        {:ok, %{message: %{content: "1. **Execute**"}, usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = Plan.run(params, context)
      assert result.model == "custom:model"
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

  defp latest_user_prompt(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: role, content: content} when role in [:user, "user"] -> content_to_string(content)
      _ -> nil
    end)
  end

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content) when is_list(content), do: Jido.AI.Turn.extract_from_content(content)
  defp content_to_string(_), do: ""
end
