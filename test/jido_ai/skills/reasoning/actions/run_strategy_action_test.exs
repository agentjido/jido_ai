defmodule Jido.AI.Actions.Reasoning.RunStrategyTest do
  @moduledoc "Successful callable methods through the real Agent, Session, and ReqLLM HTTP path."
  use Jido.AI.Test.CallableReasoningCase, async: false

  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Reasoning.TreeOfThoughts.Result
  alias Jido.Action.Error.ExecutionFailureError

  @moduletag :unit
  @moduletag :full_checkpoint

  for {strategy, method, options, calls, budget, termination} <- [
        {:cod, :chain_of_draft, %{}, 1, 1, :success},
        {:cot, :chain_of_thought, %{}, 1, 1, :success},
        {:tot, :tree_of_thoughts, %{branching_factor: 2, max_depth: 1}, 2, 802, :max_depth},
        {:got, :graph_of_thoughts, %{}, 3, 40, :success},
        {:trm, :trm, %{max_supervision_steps: 1}, 3, 3, :max_steps},
        {:aot, :algorithm_of_thoughts, %{profile: :short}, 1, 1, :success},
        {:adaptive, :chain_of_draft, %{}, 1, 1, :success}
      ] do
    script_method = if strategy == :adaptive, do: :cod, else: strategy

    test "#{strategy} completes with the expected answer and finite call budget", %{jido: jido} do
      strategy = unquote(strategy)
      script_method = unquote(script_method)
      params = %{strategy: strategy, prompt: "What is 2 + 2?", options: unquote(Macro.escape(options))}

      assert {{:ok, payload}, requests, selection} = call(jido, params, script(script_method), unquote(budget))
      details = assert_success(payload, strategy, unquote(method), unquote(calls), unquote(termination))
      assert length(requests) == unquote(calls)
      assert_answer(script_method, payload.output, details)

      for request <- requests do
        assert request.path == "/v1/chat/completions"
        assert request.body["model"] == "gpt-4o-mini"
        assert is_list(request.body["messages"])
      end

      assert_selection(strategy, details, selection, :cod, :simple_query)
    end
  end

  for strategy <- [:trm, :adaptive] do
    test "#{strategy} permits all five default TRM cycles and 15 model calls", %{jido: jido} do
      strategy = unquote(strategy)
      params = %{strategy: strategy, prompt: "Improve this answer"}
      assert {{:ok, payload}, requests, selection} = call(jido, params, five_trm_cycles(), 15)
      details = assert_success(payload, strategy, :trm, 15, :max_steps)
      assert payload.output == "Improvement 5"
      assert length(requests) == 15
      assert details.trm.supervision_step == 5
      assert details.trm.max_supervision_steps == 5
      assert details.trm.answer_history == Enum.map(1..5, &"Improvement #{&1}")
      assert details.trm.termination_reason == :max_steps
      refute details.trm.act_triggered

      assert_selection(strategy, details, selection, :trm, :iterative_reasoning)
    end
  end

  test "TRM can stop at its confidence threshold before the default limit", %{jido: jido} do
    assert {{:ok, payload}, requests, nil} =
             call(jido, %{strategy: :trm, prompt: "Improve this answer"}, script(:trm), 15)

    details = assert_success(payload, :trm, :trm, 3, :act_threshold)
    assert payload.output == "Improved answer"
    assert length(requests) == 3
    assert details.trm.supervision_step == 1
    assert details.trm.act_triggered
  end

  test "Adaptive selects ReAct for a tool request and completes without tool calls", %{jido: jido} do
    assert {{:ok, payload}, requests, selection} =
             call(jido, %{strategy: :adaptive, prompt: "Calculate two plus two"}, script(:react), 10)

    assert payload.output == "Four"
    assert payload.status == :success
    assert payload.strategy == :adaptive
    assert payload.usage.total_tokens == 15
    assert payload.diagnostics.snapshot_done
    details = payload.diagnostics.snapshot_details
    assert details.model_calls == 1
    assert details.termination_reason == :final_answer
    assert details.adaptive == selection
    assert selection.strategy == :react
    assert selection.method == :react
    assert selection.task_type == :tool_use
    assert length(requests) == 1
    refute Map.has_key?(payload.diagnostics, :error)
    refute Map.has_key?(payload.diagnostics, :recovered_error)
  end

  test "Adaptive falls back to available CoT when ReAct is unavailable", %{jido: jido} do
    params = %{strategy: :adaptive, prompt: "Calculate two plus two", available_strategies: [:cot]}
    assert {{:ok, payload}, requests, selection} = call(jido, params, script(:cot), 1)
    details = assert_success(payload, :adaptive, :chain_of_thought, 1, :success)
    assert payload.output == "Four"
    assert details.adaptive == selection
    assert selection.strategy == :cot
    assert selection.source == :automatic
    assert selection.task_type == :tool_use
    assert length(requests) == 1
  end

  test "Adaptive fallback resolves the selected TRM budget before execution", %{jido: jido} do
    params = %{strategy: :adaptive, prompt: "What is 2 + 2?", available_strategies: [:trm]}
    assert {{:ok, payload}, requests, selection} = call(jido, params, five_trm_cycles(), 15)
    details = assert_success(payload, :adaptive, :trm, 15, :max_steps)
    assert payload.output == "Improvement 5"
    assert details.trm.supervision_step == 5
    assert details.adaptive == selection
    assert selection.strategy == :trm
    assert selection.task_type == :simple_query
    assert length(requests) == 15
  end

  test "plugin-state defaults reach a successful call and its HTTP prompt", %{jido: jido} do
    params = %{strategy: :cot, prompt: "Use defaults from plugin state"}

    context = %{
      provided_params: [:strategy, :prompt, :model],
      plugin_state: %{reasoning_cot: %{timeout: 5_000, options: %{system_prompt: "Use these facts"}}}
    }

    assert {{:ok, payload}, [request], nil} = call(jido, params, script(:cot), 1, context)
    assert_success(payload, :cot, :chain_of_thought, 1, :success)
    assert payload.output == "Four"
    assert payload.diagnostics.timeout == 5_000
    assert payload.diagnostics.options.system_prompt == "Use these facts"
    assert hd(request.body["messages"])["content"] == "Use these facts"
  end

  test "returns error for invalid strategy request" do
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{prompt: "Missing strategy"}, %{})
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :cot}, %{})
  end

  test "AoT without an explicit answer returns failure data and closes the runtime", %{jido: jido} do
    response = "No explicit answer is available."

    assert {{:error, %ExecutionFailureError{details: %{reason: payload}}}, [_request], nil} =
             call(jido, %{strategy: :aot, prompt: "Solve this problem"}, [text_reply(response)], 1)

    assert_failure(payload, :aot, 1)
    refute payload.output.found_solution?
    assert payload.output.raw_response == response
    assert payload.output.usage.total_tokens == 15
    assert payload.output.termination.reason == :no_solution
  end

  test "ToT evaluation failure retains its tree and completed usage", %{jido: jido} do
    replies = [hd(script(:tot)), %{reply: {:error, 503, "Score unavailable"}}]
    params = %{strategy: :tot, prompt: "Choose a path", branching_factor: 2, max_depth: 1}

    assert {{:error, %ExecutionFailureError{details: %{reason: payload}}}, requests, nil} =
             call(jido, params, replies, 802)

    assert_failure(payload, :tot, 1)
    assert length(requests) == 2
    assert payload.output.termination.status == "error"
    assert payload.output.termination.reason == :error
    assert payload.output.tree.max_depth == 1
    assert payload.output.usage.total_tokens == 15
    assert map_size(payload.output.diagnostics.nodes) == 1
    assert hd(Map.values(payload.output.diagnostics.nodes)).content == "Choose a path"
  end

  test "TRM supervision failure retains its phase and completed usage", %{jido: jido} do
    replies = [text_reply("First answer"), %{reply: {:error, 503, "Review unavailable"}}]
    params = %{strategy: :trm, prompt: "Improve this answer", max_supervision_steps: 1}

    assert {{:error, %ExecutionFailureError{details: %{reason: payload}}}, requests, nil} =
             call(jido, params, replies, 3)

    assert_failure(payload, :trm, 1)
    assert length(requests) == 2
    details = payload.diagnostics.snapshot_details
    assert details.trm.status == :error
    assert details.trm.termination_reason == :error
    assert details.diagnostics.phase == :supervision
  end

  defp assert_failure(payload, strategy, completed_calls) do
    assert payload.strategy == strategy
    assert payload.status == :failure
    assert payload.usage.total_tokens == completed_calls * 15
    assert payload.diagnostics.snapshot_done
    assert payload.diagnostics.snapshot_status == :failure
    assert is_binary(payload.diagnostics.error)
    refute Map.has_key?(payload.diagnostics, :recovered_error)
  end

  defp assert_selection(:adaptive, details, selection, selected, task_type) do
    assert details.adaptive == selection
    assert selection.strategy == selected
    assert selection.method == details.method
    assert selection.source == :automatic
    assert selection.task_type == task_type
    assert selection.complexity_score < 0.3
  end

  defp assert_selection(_strategy, details, selection, _selected, _task_type) do
    assert selection == nil
    refute Map.has_key?(details, :adaptive)
  end

  defp assert_answer(method, output, details) when method in [:cod, :cot] do
    assert output == "Four"
    assert details.conclusion == "Four"
    assert details.steps == [%{number: 1, content: "Add two and two."}]
  end

  defp assert_answer(:tot, output, details) do
    assert Result.best_answer(output) == "Better path"
    assert Enum.map(output.candidates, &{&1.content, &1.score}) == [{"Better path", 0.8}, {"First path", 0.4}]
    assert output.termination.reason == :max_depth
    assert output.termination.node_count == 3
    assert output.tree.max_depth == 1
    assert details.result == output
  end

  defp assert_answer(:got, output, details) do
    assert output == "Combined conclusion"
    assert details.graph.status == :completed
    assert details.graph.termination_reason == :success
    assert details.graph.result == output
  end

  defp assert_answer(:trm, output, details) do
    assert output == "Improved answer"
    assert details.trm.status == :completed
    assert details.trm.supervision_step == 1
    assert details.trm.answer_history == [output]
  end

  defp assert_answer(:aot, output, details) do
    assert output.answer == "(4 + (8 - 6)) * 4 = 24"
    assert output.found_solution?
    assert output.backtracking_steps == 3
    assert output.diagnostics.explicit_answer_found
    assert output.termination.reason == :success
    assert details.result == output
  end
end
