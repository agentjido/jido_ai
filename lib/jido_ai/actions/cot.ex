defmodule Jido.AI.Actions.CoT do
  @moduledoc """
  Chain-of-Thought reasoning actions for Jido agents.

  This module provides a collection of actions that enable step-by-step reasoning
  capabilities when the CoT skill is mounted on an agent:

  - `GenerateReasoning`: Generate reasoning with mode support (zero_shot, few_shot, structured)
  - `ReasoningStep`: Execute action with thought logging
  - `ValidateReasoning`: Compare outcomes to expectations
  - `SelfCorrect`: Error recovery action

  These actions work in conjunction with the ChainOfThought skill to provide
  comprehensive reasoning capabilities.
  """

  defmodule GenerateReasoning do
    @moduledoc """
    Generates reasoning for a given problem using various CoT modes.

    Supports multiple reasoning modes:
    - `:zero_shot` - Simple "Let's think step by step" reasoning
    - `:few_shot` - Reasoning with examples
    - `:structured` - Task-specific structured reasoning
    - `:self_consistency` - Multiple reasoning samples with voting

    The action uses the agent's CoT configuration or accepts mode as a parameter.
    """

    use Jido.Action,
      name: "generate_reasoning",
      description: "Generates Chain-of-Thought reasoning for a problem",
      schema: [
        problem: [
          type: :string,
          required: true,
          doc: "The problem or query to reason about"
        ],
        mode: [
          type: {:in, [:zero_shot, :few_shot, :structured, :self_consistency]},
          default: :zero_shot,
          doc: "Reasoning mode to use"
        ],
        context: [
          type: :map,
          default: %{},
          doc: "Additional context for reasoning"
        ],
        model: [
          type: :string,
          default: "gpt-4o",
          doc: "LLM model to use for reasoning"
        ],
        temperature: [
          type: :float,
          default: 0.7,
          doc: "Temperature for reasoning generation"
        ],
        max_tokens: [
          type: :pos_integer,
          default: 2000,
          doc: "Maximum tokens for reasoning"
        ]
      ],
      output_schema: [
        reasoning: [
          type: :map,
          required: true,
          doc: "Generated reasoning structure"
        ]
      ]

    require Logger
    alias Jido.AI.Actions.TextCompletion
    alias Jido.AI.{Model, Prompt}

    @impl true
    def run(params, _context) do
      with {:ok, prompt} <- build_reasoning_prompt(params),
           {:ok, model} <- build_model(params),
           {:ok, completion} <- generate_reasoning(prompt, model, params),
           {:ok, reasoning} <- parse_reasoning(completion, params.mode) do
        {:ok, %{reasoning: reasoning}}
      else
        {:error, reason} = error ->
          Logger.error("Generate reasoning failed: #{inspect(reason)}")
          error
      end
    end

    @spec build_reasoning_prompt(map()) :: {:ok, Prompt.t()} | {:error, term()}
    defp build_reasoning_prompt(params) do
      template = get_prompt_template(params.mode)
      content = interpolate_template(template, params)

      prompt = Prompt.new(:user, content)
      {:ok, prompt}
    end

    @spec get_prompt_template(atom()) :: String.t()
    defp get_prompt_template(:zero_shot) do
      """
      Problem: {{problem}}

      Let's think step by step to solve this problem.

      {{context}}
      """
    end

    defp get_prompt_template(:few_shot) do
      """
      I'll show you how to reason through problems step by step.

      Problem: {{problem}}

      {{context}}

      Now, let's break this down step by step:
      """
    end

    defp get_prompt_template(:structured) do
      """
      Analyze the following problem using structured reasoning:

      Problem: {{problem}}

      Please structure your reasoning as follows:
      1. Problem Understanding: What is being asked?
      2. Key Information: What information is relevant?
      3. Approach: What strategy will solve this?
      4. Step-by-Step Solution: Break down the solution
      5. Verification: Check the solution

      {{context}}
      """
    end

    defp get_prompt_template(:self_consistency) do
      """
      Problem: {{problem}}

      Think through this problem carefully, considering multiple approaches.

      {{context}}

      Reason through this step by step:
      """
    end

    @spec interpolate_template(String.t(), map()) :: String.t()
    defp interpolate_template(template, params) do
      template
      |> String.replace("{{problem}}", params.problem)
      |> String.replace("{{context}}", format_context(params.context))
    end

    @spec format_context(map()) :: String.t()
    defp format_context(context) when context == %{}, do: ""

    defp format_context(context) do
      context
      |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> then(&"Additional Context:\n#{&1}")
    end

    @spec build_model(map()) :: {:ok, Model.t()} | {:error, term()}
    defp build_model(params) do
      # Parse model string to extract provider and model name
      model_parts = String.split(params.model, "/", parts: 2)

      {provider, model_name} =
        case model_parts do
          [single_part] ->
            # No provider specified, infer from model name
            infer_provider(single_part)

          [provider_str, model_str] ->
            {String.to_atom(provider_str), model_str}
        end

      model = %Model{
        provider: provider,
        model: model_name,
        temperature: params.temperature,
        max_tokens: params.max_tokens
      }

      {:ok, model}
    rescue
      error ->
        {:error, "Failed to build model: #{inspect(error)}"}
    end

    @spec infer_provider(String.t()) :: {atom(), String.t()}
    defp infer_provider("gpt-" <> _ = model), do: {:openai, model}
    defp infer_provider("claude-" <> _ = model), do: {:anthropic, model}
    defp infer_provider("gemini-" <> _ = model), do: {:google, model}
    defp infer_provider(model), do: {:openai, model}

    @spec generate_reasoning(Prompt.t(), Model.t(), map()) :: {:ok, String.t()} | {:error, term()}
    defp generate_reasoning(prompt, model, params) do
      completion_params = %{
        model: model,
        prompt: prompt,
        temperature: params.temperature,
        max_tokens: params.max_tokens
      }

      case TextCompletion.run(completion_params, %{}) do
        {:ok, %{content: content}} ->
          {:ok, content}

        {:ok, %{content: content}, _meta} ->
          {:ok, content}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @spec parse_reasoning(String.t(), atom()) :: {:ok, map()} | {:error, term()}
    defp parse_reasoning(content, mode) do
      reasoning = %{
        mode: mode,
        content: content,
        steps: extract_steps(content),
        timestamp: DateTime.utc_now()
      }

      {:ok, reasoning}
    end

    @spec extract_steps(String.t()) :: list(String.t())
    defp extract_steps(content) do
      # Simple step extraction - look for numbered or bulleted lists
      content
      |> String.split("\n")
      |> Enum.filter(fn line ->
        String.match?(line, ~r/^(\d+\.|\*|-)\s+/) or
          String.match?(line, ~r/^Step \d+:/)
      end)
      |> Enum.map(&String.trim/1)
    end
  end

  defmodule ReasoningStep do
    @moduledoc """
    Executes an action while logging the reasoning/thought process.

    This action wraps another action and captures:
    - The thought/reasoning before execution
    - The action execution
    - The result and any observations

    This enables transparent reasoning traces for debugging and validation.
    """

    use Jido.Action,
      name: "reasoning_step",
      description: "Execute action with thought logging",
      schema: [
        thought: [
          type: :string,
          required: true,
          doc: "The reasoning thought for this step"
        ],
        action: [
          type: :atom,
          required: true,
          doc: "The action module to execute"
        ],
        params: [
          type: :map,
          default: %{},
          doc: "Parameters for the action"
        ],
        step_index: [
          type: :non_neg_integer,
          default: 0,
          doc: "Index of this step in the reasoning trace"
        ]
      ],
      output_schema: [
        step: [
          type: :map,
          required: true,
          doc: "Executed step with results"
        ]
      ]

    require Logger

    @impl true
    def run(params, context) do
      step_start = DateTime.utc_now()

      Logger.debug("""
      [CoT Step #{params.step_index}]
      Thought: #{params.thought}
      Action: #{inspect(params.action)}
      """)

      case execute_action(params.action, params.params, context) do
        {:ok, result} ->
          step = %{
            index: params.step_index,
            thought: params.thought,
            action: params.action,
            params: params.params,
            result: result,
            timestamp: step_start,
            duration_ms: DateTime.diff(DateTime.utc_now(), step_start, :millisecond)
          }

          Logger.debug("[CoT Step #{params.step_index}] Completed: #{inspect(result)}")

          {:ok, %{step: step}}

        {:error, reason} ->
          Logger.error("[CoT Step #{params.step_index}] Failed: #{inspect(reason)}")

          step = %{
            index: params.step_index,
            thought: params.thought,
            action: params.action,
            params: params.params,
            error: reason,
            timestamp: step_start,
            duration_ms: DateTime.diff(DateTime.utc_now(), step_start, :millisecond)
          }

          # Return the step with error info
          {:ok, %{step: step, error: reason}}
      end
    end

    @spec execute_action(atom(), map(), map()) :: {:ok, term()} | {:error, term()}
    defp execute_action(action_module, params, context) do
      if Code.ensure_loaded?(action_module) and function_exported?(action_module, :run, 2) do
        case action_module.run(params, context) do
          {:ok, result} -> {:ok, result}
          {:ok, result, _meta} -> {:ok, result}
          {:error, reason} -> {:error, reason}
          other -> {:error, "Unexpected action result: #{inspect(other)}"}
        end
      else
        {:error, "Action module #{inspect(action_module)} not found or invalid"}
      end
    end
  end

  defmodule ValidateReasoning do
    @moduledoc """
    Validates execution results against reasoning expectations.

    This action compares:
    - Expected outcomes from reasoning
    - Actual execution results
    - Identifies discrepancies and generates recommendations

    Similar to the ValidationHook but as a standalone action.
    """

    use Jido.Action,
      name: "validate_reasoning",
      description: "Compare outcomes to reasoning expectations",
      schema: [
        reasoning: [
          type: :map,
          required: true,
          doc: "The reasoning that was generated"
        ],
        result: [
          type: :map,
          required: true,
          doc: "The actual execution result"
        ],
        tolerance: [
          type: :float,
          default: 0.8,
          doc: "Match tolerance (0.0-1.0)"
        ],
        generate_reflection: [
          type: :boolean,
          default: true,
          doc: "Generate reflection on validation"
        ]
      ],
      output_schema: [
        validation: [
          type: :map,
          required: true,
          doc: "Validation result"
        ]
      ]

    require Logger

    @impl true
    def run(params, _context) do
      {:ok, validation} = perform_validation(params)

      Logger.info("""
      [CoT Validation]
      Status: #{validation.status}
      Match Score: #{Float.round(validation.match_score, 2)}
      Recommendation: #{validation.recommendation}
      """)

      {:ok, %{validation: validation}}
    end

    @spec perform_validation(map()) :: {:ok, map()} | {:error, term()}
    defp perform_validation(params) do
      status = determine_status(params.result, params.reasoning, params.tolerance)
      match_score = calculate_match_score(params.result, params.reasoning, params.tolerance)
      recommendation = determine_recommendation(status, match_score, params.tolerance)

      validation = %{
        status: status,
        match_score: match_score,
        recommendation: recommendation,
        reasoning_summary: summarize_reasoning(params.reasoning),
        result_summary: summarize_result(params.result),
        timestamp: DateTime.utc_now()
      }

      {:ok, validation}
    end

    @spec determine_status(map(), map(), float()) :: atom()
    defp determine_status(%{error: _}, _reasoning, _tolerance), do: :error

    defp determine_status(result, reasoning, tolerance) do
      score = calculate_match_score(result, reasoning, tolerance)

      cond do
        score >= tolerance -> :success
        score >= tolerance * 0.5 -> :partial_success
        true -> :unexpected
      end
    end

    @spec calculate_match_score(map(), map(), float()) :: float()
    defp calculate_match_score(result, _reasoning, _tolerance) do
      # Simple scoring based on result success
      cond do
        Map.has_key?(result, :error) -> 0.0
        Map.has_key?(result, :success) and result.success -> 1.0
        is_map(result) and map_size(result) > 0 -> 0.8
        true -> 0.5
      end
    end

    @spec determine_recommendation(atom(), float(), float()) :: atom()
    defp determine_recommendation(:success, _score, _tolerance), do: :continue

    defp determine_recommendation(:partial_success, score, tolerance) when score >= tolerance,
      do: :continue

    defp determine_recommendation(:partial_success, _score, _tolerance), do: :investigate
    defp determine_recommendation(:unexpected, _score, _tolerance), do: :retry
    defp determine_recommendation(:error, _score, _tolerance), do: :retry

    @spec summarize_reasoning(map()) :: String.t()
    defp summarize_reasoning(%{content: content}) when is_binary(content) do
      content
      |> String.slice(0..200)
      |> then(&if String.length(content) > 200, do: &1 <> "...", else: &1)
    end

    defp summarize_reasoning(reasoning), do: inspect(reasoning, limit: 200)

    @spec summarize_result(map()) :: String.t()
    defp summarize_result(result), do: inspect(result, limit: 200)
  end

  defmodule SelfCorrect do
    @moduledoc """
    Analyzes errors and proposes corrections for failed reasoning attempts.

    This action:
    - Analyzes the error or unexpected result
    - Identifies what went wrong
    - Proposes corrections or alternative approaches
    - Adjusts parameters for retry

    This enables automatic error recovery and iterative refinement.
    """

    use Jido.Action,
      name: "self_correct",
      description: "Error recovery and correction action",
      schema: [
        error: [
          type: :map,
          required: true,
          doc: "The error or validation failure"
        ],
        reasoning: [
          type: :map,
          required: true,
          doc: "The original reasoning"
        ],
        attempt: [
          type: :non_neg_integer,
          default: 0,
          doc: "Retry attempt number"
        ],
        max_attempts: [
          type: :pos_integer,
          default: 3,
          doc: "Maximum retry attempts"
        ],
        adjust_temperature: [
          type: :float,
          default: 0.1,
          doc: "Temperature adjustment for retry"
        ]
      ],
      output_schema: [
        correction: [
          type: :map,
          required: true,
          doc: "Correction strategy"
        ]
      ]

    require Logger

    @impl true
    def run(params, _context) do
      if params.attempt >= params.max_attempts do
        Logger.warning("Max correction attempts (#{params.max_attempts}) reached")

        {:ok,
         %{
           correction: %{
             should_retry: false,
             reason: :max_attempts_exceeded,
             attempt: params.attempt
           }
         }}
      else
        {:ok, correction} = analyze_error(params)

        Logger.info("""
        [CoT Self-Correction]
        Attempt: #{params.attempt + 1}/#{params.max_attempts}
        Analysis: #{correction.analysis}
        Strategy: #{correction.strategy}
        """)

        {:ok, %{correction: correction}}
      end
    end

    @spec analyze_error(map()) :: {:ok, map()} | {:error, term()}
    defp analyze_error(params) do
      error_type = classify_error(params.error)
      analysis = generate_analysis(error_type, params.error, params.reasoning)
      strategy = determine_strategy(error_type, params)

      # Ensure adjust_temperature is available for calculations
      adjust_temp = Map.get(params, :adjust_temperature, 0.1)
      adjustments = calculate_adjustments(strategy, params.attempt, adjust_temp)

      correction = %{
        should_retry: strategy != :abandon,
        error_type: error_type,
        analysis: analysis,
        strategy: strategy,
        adjustments: adjustments,
        attempt: params.attempt + 1,
        timestamp: DateTime.utc_now()
      }

      {:ok, correction}
    end

    @spec classify_error(map()) :: atom()
    defp classify_error(%{status: :error}), do: :execution_error
    defp classify_error(%{status: :unexpected}), do: :unexpected_result
    defp classify_error(%{status: :partial_success}), do: :partial_failure
    defp classify_error(%{error: _}), do: :runtime_error
    defp classify_error(_), do: :unknown_error

    @spec generate_analysis(atom(), map(), map()) :: String.t()
    defp generate_analysis(:execution_error, error, _reasoning) do
      "Execution failed with error: #{inspect(Map.get(error, :error, "unknown"))}"
    end

    defp generate_analysis(:unexpected_result, error, reasoning) do
      "Result did not match reasoning expectations. " <>
        "Expected pattern from reasoning mode #{Map.get(reasoning, :mode, :unknown)}, " <>
        "but got: #{inspect(error)}"
    end

    defp generate_analysis(:partial_failure, error, _reasoning) do
      "Partial success with score #{Map.get(error, :match_score, 0.0)}"
    end

    defp generate_analysis(:runtime_error, error, _reasoning) do
      "Runtime error occurred: #{inspect(error)}"
    end

    defp generate_analysis(:unknown_error, error, _reasoning) do
      "Unknown error: #{inspect(error)}"
    end

    @spec determine_strategy(atom(), map()) :: atom()
    defp determine_strategy(_error_type, %{attempt: attempt, max_attempts: max})
         when attempt >= max do
      :abandon
    end

    defp determine_strategy(:execution_error, _params), do: :adjust_and_retry
    defp determine_strategy(:unexpected_result, _params), do: :increase_temperature
    defp determine_strategy(:partial_failure, _params), do: :refine_approach
    defp determine_strategy(:runtime_error, _params), do: :adjust_and_retry
    defp determine_strategy(:unknown_error, _params), do: :adjust_and_retry

    @spec calculate_adjustments(atom(), non_neg_integer(), float()) :: map()
    defp calculate_adjustments(:abandon, _attempt, _adjust_temp), do: %{}

    defp calculate_adjustments(:adjust_and_retry, attempt, adjust_temp) do
      %{
        temperature: 0.7 + adjust_temp * attempt,
        max_tokens: 2000
      }
    end

    defp calculate_adjustments(:increase_temperature, attempt, adjust_temp) do
      %{
        temperature: min(0.7 + adjust_temp * (attempt + 1), 1.0),
        max_tokens: 2000
      }
    end

    defp calculate_adjustments(:refine_approach, attempt, adjust_temp) do
      %{
        temperature: 0.7 + adjust_temp * 0.5 * attempt,
        max_tokens: 2500
      }
    end

    defp calculate_adjustments(_, _attempt, _adjust_temp),
      do: %{temperature: 0.7, max_tokens: 2000}
  end
end
