Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.Reasoning.{Analyze, Explain, Infer, RunStrategy}
alias Jido.AI.Examples.Scripts.Bootstrap

defmodule ActionsReasoningRuntimeDemo.Helpers do
  def run!(action, params, opts \\ [], attempts \\ 3) do
    case run_with_retry(action, params, opts, attempts) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise "Action #{inspect(action)} failed after #{attempts} attempt(s): #{inspect(reason)}"
    end
  end

  defp run_with_retry(action, params, opts, attempts) when attempts > 0 do
    case Jido.Exec.run(action, params, %{}, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempts > 1 and retryable?(reason) do
          Process.sleep(backoff_ms(attempts))
          run_with_retry(action, params, opts, attempts - 1)
        else
          {:error, reason}
        end
    end
  end

  defp backoff_ms(attempts_left), do: (4 - attempts_left) * 1_000 + 1_000

  defp retryable?(%Jido.Action.Error.TimeoutError{}), do: true

  defp retryable?(reason) do
    inspected = String.downcase(inspect(reason))
    String.contains?(inspected, "overloaded") or String.contains?(inspected, "timeout")
  end
end

Bootstrap.init!(required_env: ["ANTHROPIC_API_KEY"])
Bootstrap.print_banner("Actions Reasoning Runtime Demo")

analyze =
  ActionsReasoningRuntimeDemo.Helpers.run!(
    Analyze,
    %{
      input: "Customer churn increased 18% this quarter while support volume stayed flat.",
      analysis_type: :summary
    },
    timeout: 120_000
  )

Bootstrap.assert!(is_map(analyze), "Analyze action did not return a map.")

infer =
  ActionsReasoningRuntimeDemo.Helpers.run!(
    Infer,
    %{
      premises: "All production incidents trigger a postmortem. Incident INC-42 was a production incident.",
      question: "Should INC-42 have a postmortem?"
    },
    timeout: 120_000
  )

Bootstrap.assert!(is_map(infer), "Infer action did not return a map.")

explain =
  ActionsReasoningRuntimeDemo.Helpers.run!(
    Explain,
    %{
      topic: "GenServer supervision trees",
      detail_level: :intermediate,
      audience: "backend engineers",
      include_examples: true
    },
    timeout: 120_000
  )

Bootstrap.assert!(is_map(explain), "Explain action did not return a map.")

strategy_run =
  ActionsReasoningRuntimeDemo.Helpers.run!(
    RunStrategy,
    %{
      strategy: :cot,
      prompt: "Recommend one rollout option and include a fallback in three bullets.",
      options: %{llm_timeout_ms: 60_000}
    },
    timeout: 180_000
  )

Bootstrap.assert!(is_map(strategy_run), "RunStrategy action did not return a map.")

IO.puts("✓ Reasoning actions analyze/infer/explain/run_strategy passed")
