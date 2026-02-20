defmodule Jido.AI.Actions.Reasoning.RunStrategyTest do
  @moduledoc """
  Full-checkpoint coverage for `RunStrategy`.

  This file keeps the comprehensive strategy matrix and plugin-default behavior.
  Fast-smoke coverage lives in `run_strategy_action_fast_test.exs`.
  """

  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :full_checkpoint
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  defp assert_strategy_response({:ok, payload}, strategy) do
    assert payload.strategy == strategy
    assert payload.status in [:success, :running, :idle, :failure]
    assert is_map(payload.usage)
    assert is_map(payload.diagnostics)
    payload
  end

  defp assert_strategy_response({:error, payload}, strategy) do
    assert payload.strategy == strategy
    assert payload.status in [:success, :running, :idle, :failure]
    assert is_map(payload.usage)
    assert is_map(payload.diagnostics)
    assert Map.has_key?(payload.diagnostics, :error)
    payload
  end

  describe "run/2" do
    test "executes Chain-of-Draft strategy" do
      params = %{strategy: :cod, prompt: "Answer tersely with drafts", timeout: 10_000}
      payload = assert_strategy_response(RunStrategy.run(params, %{}), :cod)
      assert not is_nil(payload.output)
    end

    test "executes Chain-of-Thought strategy" do
      params = %{strategy: :cot, prompt: "Explain 2+2", timeout: 10_000}
      payload = assert_strategy_response(RunStrategy.run(params, %{}), :cot)
      assert not is_nil(payload.output)
    end

    test "executes Tree-of-Thoughts strategy" do
      params = %{
        strategy: :tot,
        prompt: "Explore solution paths",
        timeout: 10_000,
        options: %{branching_factor: 1, max_depth: 1}
      }

      assert_strategy_response(RunStrategy.run(params, %{}), :tot)
    end

    test "executes Graph-of-Thoughts strategy" do
      params = %{
        strategy: :got,
        prompt: "Synthesize multiple viewpoints",
        timeout: 10_000,
        options: %{max_nodes: 2, max_depth: 1}
      }

      assert_strategy_response(RunStrategy.run(params, %{}), :got)
    end

    test "executes TRM strategy" do
      params = %{
        strategy: :trm,
        prompt: "Iteratively improve this answer",
        timeout: 10_000,
        options: %{max_supervision_steps: 1}
      }

      assert_strategy_response(RunStrategy.run(params, %{}), :trm)
    end

    test "executes Algorithm-of-Thoughts strategy" do
      params = %{
        strategy: :aot,
        prompt: "Explore options and finalize explicitly",
        timeout: 10_000,
        options: %{profile: :short, search_style: :dfs}
      }

      assert_strategy_response(RunStrategy.run(params, %{}), :aot)
    end

    test "executes Adaptive strategy" do
      params = %{
        strategy: :adaptive,
        prompt: "Choose the best reasoning approach",
        timeout: 10_000,
        options: %{default_strategy: :cot, available_strategies: [:cot]}
      }

      assert_strategy_response(RunStrategy.run(params, %{}), :adaptive)
    end

    test "applies plugin-state defaults for timeout and options" do
      params = %{strategy: :cot, prompt: "Use defaults from plugin state"}

      context = %{
        provided_params: [:strategy, :prompt],
        plugin_state: %{
          reasoning_cot: %{
            default_model: :fast,
            timeout: 4_000,
            options: %{system_prompt: "Reason carefully"}
          }
        }
      }

      payload = assert_strategy_response(RunStrategy.run(params, context), :cot)
      assert payload.diagnostics.timeout == 4_000
      assert payload.diagnostics.options[:system_prompt] == "Reason carefully"
    end

    test "returns error for invalid strategy request" do
      assert {:error, :invalid_strategy_request} = RunStrategy.run(%{prompt: "Missing strategy"}, %{})
      assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :cot}, %{})
    end
  end
end
