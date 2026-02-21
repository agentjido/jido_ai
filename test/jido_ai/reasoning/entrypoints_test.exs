defmodule Jido.AI.Reasoning.EntrypointsTest do
  use ExUnit.Case, async: true

  @strategy_modules [
    {Jido.AI.Reasoning.Adaptive, Jido.AI.Reasoning.Adaptive.Strategy},
    {Jido.AI.Reasoning.AlgorithmOfThoughts, Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy},
    {Jido.AI.Reasoning.ChainOfDraft, Jido.AI.Reasoning.ChainOfDraft.Strategy},
    {Jido.AI.Reasoning.ChainOfThought, Jido.AI.Reasoning.ChainOfThought.Strategy},
    {Jido.AI.Reasoning.GraphOfThoughts, Jido.AI.Reasoning.GraphOfThoughts.Strategy},
    {Jido.AI.Reasoning.TreeOfThoughts, Jido.AI.Reasoning.TreeOfThoughts.Strategy},
    {Jido.AI.Reasoning.TRM, Jido.AI.Reasoning.TRM.Strategy}
  ]

  describe "strategy_module/0 delegation" do
    for {entrypoint, strategy} <- @strategy_modules do
      test "#{inspect(entrypoint)} returns canonical strategy module" do
        assert unquote(entrypoint).strategy_module() == unquote(strategy)
      end
    end
  end

  describe "delegated helper contracts" do
    test "Adaptive.analyze_prompt/2 returns strategy metadata tuple" do
      assert {strategy, score, task_type} = Jido.AI.Reasoning.Adaptive.analyze_prompt("What is 2 + 2?", %{})
      assert is_atom(strategy)
      assert is_float(score)
      assert is_atom(task_type)
    end

    test "AoT delegates generate_call_id and default prompt" do
      assert String.starts_with?(Jido.AI.Reasoning.AlgorithmOfThoughts.generate_call_id(), "aot_")

      assert is_binary(Jido.AI.Reasoning.AlgorithmOfThoughts.default_system_prompt(:standard, :dfs, []))
    end

    test "CoD delegates prompt, call id, and extraction helper" do
      assert is_binary(Jido.AI.Reasoning.ChainOfDraft.default_system_prompt())
      assert String.starts_with?(Jido.AI.Reasoning.ChainOfDraft.generate_call_id(), "cod_")

      {steps, conclusion} =
        Jido.AI.Reasoning.ChainOfDraft.extract_steps_and_conclusion("Step 1: Think.\n#### Final answer")

      assert is_list(steps)
      assert is_binary(conclusion) or is_nil(conclusion)
    end

    test "CoT delegates prompt, call id, and extraction helper" do
      assert is_binary(Jido.AI.Reasoning.ChainOfThought.default_system_prompt())
      assert String.starts_with?(Jido.AI.Reasoning.ChainOfThought.generate_call_id(), "cot_")

      {steps, conclusion} =
        Jido.AI.Reasoning.ChainOfThought.extract_steps_and_conclusion("1) Think.\n#### Answer")

      assert is_list(steps)
      assert is_binary(conclusion) or is_nil(conclusion)
    end

    test "GoT delegates call id and prompt helpers" do
      assert String.starts_with?(Jido.AI.Reasoning.GraphOfThoughts.generate_call_id(), "got_")
      assert is_binary(Jido.AI.Reasoning.GraphOfThoughts.default_generation_prompt())
      assert is_binary(Jido.AI.Reasoning.GraphOfThoughts.default_connection_prompt())
      assert is_binary(Jido.AI.Reasoning.GraphOfThoughts.default_aggregation_prompt())
    end

    test "ToT delegates call id and prompt helpers" do
      assert String.starts_with?(Jido.AI.Reasoning.TreeOfThoughts.generate_call_id(), "tot_")
      assert is_binary(Jido.AI.Reasoning.TreeOfThoughts.default_generation_prompt())
      assert is_binary(Jido.AI.Reasoning.TreeOfThoughts.default_evaluation_prompt())
    end

    test "TRM delegates call id and prompt helpers" do
      assert String.starts_with?(Jido.AI.Reasoning.TRM.generate_call_id(), "trm_")
      assert is_binary(Jido.AI.Reasoning.TRM.default_reasoning_prompt())
      assert is_binary(Jido.AI.Reasoning.TRM.default_supervision_prompt())
      assert is_binary(Jido.AI.Reasoning.TRM.default_improvement_prompt())
    end
  end
end
