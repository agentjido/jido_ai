defmodule Jido.AI.ToTAgent do
  @moduledoc "Tree search helpers over the shared v3 Agent and Flow implementation."

  @method_keys ~w(branching_factor max_depth traversal_strategy top_k min_depth max_nodes max_duration_ms beam_width early_success_threshold convergence_window min_score_improvement max_parse_retries max_tool_round_trips generation_prompt evaluation_prompt)a

  defmacro __using__(opts) do
    options =
      opts
      |> Keyword.take(@method_keys)
      |> Jido.AI.Agent.Definition.expand_and_eval_literal_option(__CALLER__)

    normalized =
      case Jido.AI.Reasoning.options(:tree_of_thoughts, options) do
        {:ok, value} -> value
        {:error, error} -> raise error
      end

    calls = Jido.AI.Reasoning.model_call_limit(:tree_of_thoughts, normalized)

    opts =
      opts
      |> Keyword.drop(@method_keys)
      |> Keyword.put(:reasoning, :tree_of_thoughts)
      |> Keyword.put(:reasoning_options, options)
      |> Keyword.put_new(:description, "ToT agent #{Keyword.fetch!(opts, :name)}")
      |> Keyword.put_new(:max_iterations, calls)
      |> Keyword.put_new(:max_tool_calls, 10_000)
      |> Keyword.put_new(:max_tokens, 1024)
      |> Keyword.put_new(:temperature, 0.2)

    opts =
      if normalized.max_duration_ms,
        do: Keyword.put_new(opts, :llm_timeout_ms, normalized.max_duration_ms),
        else: opts

    quote do
      use Jido.AI.Agent, unquote(opts)

      def explore(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask(server, prompt, opts)

      def explore_sync(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Reads declared method settings; the AI profile owns execution policy."
      def strategy_opts do
        {:ok, options} =
          Jido.AI.Reasoning.options(:tree_of_thoughts, @jido_ai_options[:reasoning_options])

        [
          model: Keyword.get(@jido_ai_options, :model, :fast),
          tools: Keyword.get(@jido_ai_options, :tools, []),
          tool_context: Keyword.get(@jido_ai_options, :tool_context, %{}),
          tool_timeout_ms: Keyword.get(@jido_ai_options, :tool_timeout_ms, 15_000),
          tool_max_retries: Keyword.get(@jido_ai_options, :tool_max_retries, 1),
          tool_retry_backoff_ms: Keyword.get(@jido_ai_options, :tool_retry_backoff_ms, 200),
          agent_effect_policy: Keyword.get(@jido_ai_options, :effect_policy, %{}),
          strategy_effect_policy: Keyword.get(@jido_ai_options, :strategy_effect_policy, %{})
        ] ++ Enum.to_list(options)
      end

      defdelegate best_answer(result), to: Jido.AI.Reasoning.TreeOfThoughts.Result

      def top_candidates(result, limit \\ 3),
        do: Jido.AI.Reasoning.TreeOfThoughts.Result.top_candidates(result, limit)

      def result_summary(%{} = result) do
        %{
          best_answer: best_answer(result),
          top_candidates: top_candidates(result, 3),
          termination: Map.get(result, :termination, %{}),
          tree: Map.get(result, :tree, %{})
        }
      end

      def result_summary(_),
        do: %{best_answer: nil, top_candidates: [], termination: %{}, tree: %{}}

      defoverridable explore: 3, explore_sync: 3
    end
  end
end
