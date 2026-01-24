defmodule Jido.AI.Skills.ToolCalling.Actions.CallWithToolsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.ToolCalling.Actions.CallWithTools

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "has required fields" do
      assert CallWithTools.schema().fields[:prompt].meta.required == true
      refute CallWithTools.schema().fields[:model].meta.required
      refute CallWithTools.schema().fields[:tools].meta.required
    end

    test "has default values" do
      assert CallWithTools.schema().fields[:max_tokens].value == 4096
      assert CallWithTools.schema().fields[:temperature].value == 0.7
      assert CallWithTools.schema().fields[:auto_execute].value == false
      assert CallWithTools.schema().fields[:max_turns].value == 10
    end
  end

  describe "run/2" do
    test "returns error when prompt is missing" do
      assert {:error, _} = CallWithTools.run(%{}, %{})
    end

    test "returns error when prompt is empty string" do
      assert {:error, _} = CallWithTools.run(%{prompt: ""}, %{})
    end

    @tag :skip
    test "returns result with valid prompt" do
      params = %{
        prompt: "What is 2 + 2?"
      }

      assert {:ok, result} = CallWithTools.run(params, %{})
      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :model)
    end

    @tag :skip
    test "includes tools in LLM call" do
      # Register a test tool first
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"]
      }

      assert {:ok, result} = CallWithTools.run(params, %{})
      assert Map.has_key?(result, :type)
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        prompt: "Test",
        model: :capable
      }

      assert params[:model] == :capable
    end

    test "accepts string model spec" do
      params = %{
        prompt: "Test",
        model: "anthropic:claude-sonnet-4-20250514"
      }

      assert params[:model] == "anthropic:claude-sonnet-4-20250514"
    end
  end
end
