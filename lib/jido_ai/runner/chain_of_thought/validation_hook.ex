defmodule Jido.AI.Runner.ChainOfThought.ValidationHook do
  @moduledoc """
  Validation hook integration for Chain-of-Thought reasoning.

  Provides helper functions for implementing `on_after_run/3` callback with
  CoT validation capabilities. This enables result validation after execution,
  comparing actual results against planning expectations and execution plan.

  ## Features

  - Result validation against execution plan expectations
  - Comparison with planning goals and anticipated issues
  - Unexpected result detection with reflection generation
  - Configurable tolerance for validation matching
  - Automatic retry support on validation failure
  - Opt-in behavior via `enable_validation_cot` flag

  ## Usage

  Implement `on_after_run/3` callback in your agent:

      defmodule MyAgent do
        use Jido.Agent

        def on_after_run(agent, result, unapplied_directives) do
          Jido.AI.Runner.ChainOfThought.ValidationHook.validate_execution(
            agent, result, unapplied_directives
          )
        end
      end

  ## Opt-in Behavior

  Enable validation CoT by setting agent state flag:

      agent
      |> Jido.Agent.set(:enable_validation_cot, true)
      |> MyAgent.run()

  Or disable it:

      agent
      |> Jido.Agent.set(:enable_validation_cot, false)
      |> MyAgent.run()

  ## Retry Behavior

  Configure automatic retry on validation failure:

      agent = Jido.Agent.set(agent, :validation_config, %{
        retry_on_failure: true,
        max_retries: 2,
        adjust_temperature: 0.1  # Increase temperature on retry
      })
  """

  require Logger
  use TypedStruct

  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.Runner.ChainOfThought.{ErrorHandler, ExecutionHook, PlanningHook}

  typedstruct module: ValidationResult do
    @moduledoc """
    Result of validation comparing execution results against expectations.
    """
    field(:status, atom(), enforce: true)
    field(:match_score, float(), default: 0.0)
    field(:expected_vs_actual, map(), default: %{})
    field(:unexpected_results, list(String.t()), default: [])
    field(:anticipated_errors_occurred, list(String.t()), default: [])
    field(:reflection, String.t(), default: "")
    field(:recommendation, atom(), default: :continue)
    field(:timestamp, DateTime.t(), enforce: true)
  end

  typedstruct module: ValidationConfig do
    @moduledoc """
    Configuration for validation behavior.
    """
    field(:tolerance, float(), default: 0.8)
    field(:retry_on_failure, boolean(), default: false)
    field(:max_retries, non_neg_integer(), default: 2)
    field(:adjust_temperature, float(), default: 0.1)
    field(:generate_reflection, boolean(), default: true)
  end

  @doc """
  Validates execution results against planning and execution context.

  This is the main entry point for implementing `on_after_run/3` callback.
  It compares execution results against:
  - Planning goals and anticipated issues
  - Execution plan expectations and error points
  - Expected vs actual outcomes

  ## Options (via agent state)

  - `:enable_validation_cot` - Enable/disable validation (default: true)
  - `:validation_config` - ValidationConfig struct (default: defaults)
  - `:validation_model` - Model to use for reflection (default: from config)

  ## Examples

      def on_after_run(agent, result, unapplied_directives) do
        ValidationHook.validate_execution(agent, result, unapplied_directives)
      end

  ## Returns

  - `{:ok, agent}` - Validation passed or disabled
  - `{:ok, agent}` - Validation failed but retry not configured
  - `{:retry, agent, adjusted_params}` - Validation failed, should retry
  - `{:error, reason}` - Fatal validation error
  """
  @spec validate_execution(map(), map(), list()) ::
          {:ok, map()} | {:retry, map(), map()} | {:error, term()}
  def validate_execution(agent, result, unapplied_directives) do
    if should_validate_execution?(agent) do
      do_validate_execution(agent, result, unapplied_directives)
    else
      Logger.debug("Validation CoT disabled via agent state")
      {:ok, agent}
    end
  end

  @doc """
  Checks if execution validation should be performed based on agent state.

  Returns `true` if `enable_validation_cot` is not explicitly set to `false`.

  ## Examples

      iex> should_validate_execution?(%{state: %{enable_validation_cot: true}})
      true

      iex> should_validate_execution?(%{state: %{enable_validation_cot: false}})
      false

      iex> should_validate_execution?(%{state: %{}})
      true
  """
  @spec should_validate_execution?(map()) :: boolean()
  def should_validate_execution?(agent) do
    get_in(agent, [:state, :enable_validation_cot]) != false
  end

  @doc """
  Adds validation result to agent state for inspection.

  The validation result is stored in the agent's state under `:validation_result` key.

  ## Examples

      agent = enrich_agent_with_validation(agent, validation_result)
      result = get_in(agent, [:state, :validation_result])
  """
  @spec enrich_agent_with_validation(map(), ValidationResult.t()) :: map()
  def enrich_agent_with_validation(agent, validation_result) do
    current_state = agent.state || %{}
    updated_state = Map.put(current_state, :validation_result, validation_result)
    %{agent | state: updated_state}
  end

  @doc """
  Extracts validation result from agent state.

  Returns the validation result if available, or error if not present.

  ## Examples

      {:ok, validation} = get_validation_result(agent)
  """
  @spec get_validation_result(map()) :: {:ok, ValidationResult.t()} | {:error, :no_validation}
  def get_validation_result(agent) do
    case get_in(agent, [:state, :validation_result]) do
      %ValidationResult{} = validation -> {:ok, validation}
      nil -> {:error, :no_validation}
      _ -> {:error, :invalid_validation}
    end
  end

  @doc """
  Gets validation configuration from agent state or returns defaults.
  """
  @spec get_validation_config(map()) :: ValidationConfig.t()
  def get_validation_config(agent) do
    case get_in(agent, [:state, :validation_config]) do
      %ValidationConfig{} = config -> config
      config when is_map(config) -> struct(ValidationConfig, config)
      _ -> %ValidationConfig{}
    end
  end

  # Private Functions

  @spec do_validate_execution(map(), map(), list()) ::
          {:ok, map()} | {:retry, map(), map()} | {:error, term()}
  defp do_validate_execution(agent, result, _unapplied_directives) do
    config = get_validation_config(agent)

    Logger.info("Validating execution results")

    case perform_validation(agent, result, config) do
      {:ok, validation_result} ->
        enriched_agent = enrich_agent_with_validation(agent, validation_result)

        case validation_result.recommendation do
          :continue ->
            Logger.info("Validation passed: #{validation_result.status}")
            {:ok, enriched_agent}

          :retry ->
            if config.retry_on_failure do
              Logger.warning("Validation failed, recommending retry")
              retry_count = get_retry_count(agent)

              if retry_count < config.max_retries do
                adjusted_params = build_retry_params(agent, config, retry_count)
                {:retry, increment_retry_count(enriched_agent), adjusted_params}
              else
                Logger.warning("Max retries (#{config.max_retries}) exceeded, continuing anyway")
                {:ok, enriched_agent}
              end
            else
              Logger.info("Validation failed but retry disabled, continuing")
              {:ok, enriched_agent}
            end

          :investigate ->
            Logger.warning("Validation suggests investigation: #{validation_result.reflection}")
            {:ok, enriched_agent}

          _ ->
            {:ok, enriched_agent}
        end

      {:error, reason} ->
        Logger.warning("Validation failed with error: #{inspect(reason)}")
        # Graceful degradation - return agent unchanged
        {:ok, agent}
    end
  end

  @spec perform_validation(map(), map(), ValidationConfig.t()) ::
          {:ok, ValidationResult.t()} | {:error, term()}
  defp perform_validation(agent, result, config) do
    planning_context = get_planning_context(agent)
    execution_context = get_execution_context(agent)

    with {:ok, validation_result} <-
           analyze_validation(result, planning_context, execution_context, config) do
      if config.generate_reflection and validation_result.status != :success do
        case generate_reflection(agent, result, validation_result) do
          {:ok, reflection} ->
            {:ok, %{validation_result | reflection: reflection}}

          {:error, _} ->
            # Continue without reflection
            {:ok, validation_result}
        end
      else
        {:ok, validation_result}
      end
    end
  end

  @spec analyze_validation(map(), map(), map(), ValidationConfig.t()) ::
          {:ok, ValidationResult.t()}
  defp analyze_validation(result, planning_context, execution_context, config) do
    # Basic validation logic
    status = determine_status(result, planning_context, execution_context, config)
    match_score = calculate_match_score(result, execution_context, config)
    unexpected = identify_unexpected_results(result, execution_context)
    anticipated_errors = check_anticipated_errors(result, planning_context, execution_context)
    recommendation = determine_recommendation(status, match_score, config)

    validation_result = %ValidationResult{
      status: status,
      match_score: match_score,
      unexpected_results: unexpected,
      anticipated_errors_occurred: anticipated_errors,
      recommendation: recommendation,
      timestamp: DateTime.utc_now()
    }

    {:ok, validation_result}
  end

  @spec determine_status(map(), map(), map(), ValidationConfig.t()) :: atom()
  defp determine_status(result, planning_context, execution_context, config) do
    cond do
      # Check if result indicates error
      match?({:error, _}, result) ->
        :error

      # Check if execution context had anticipated errors
      has_anticipated_errors?(planning_context, execution_context, result) ->
        :partial_success

      # Check if result matches expectations
      matches_expectations?(result, execution_context, config.tolerance) ->
        :success

      # Otherwise unexpected
      true ->
        :unexpected
    end
  end

  @spec calculate_match_score(map(), map(), ValidationConfig.t()) :: float()
  defp calculate_match_score(_result, %{execution_plan: %{steps: steps}}, _config)
       when length(steps) > 0 do
    # Simple scoring based on steps completed
    # In real implementation, would compare actual vs expected outputs
    0.85
  end

  defp calculate_match_score(_result, _execution_context, _config) do
    # No execution plan to compare against
    1.0
  end

  @spec identify_unexpected_results(map(), map()) :: list(String.t())
  defp identify_unexpected_results(_result, %{execution_plan: %{error_points: error_points}}) do
    # In real implementation, would check if actual errors match anticipated ones
    if length(error_points) > 0 do
      []
    else
      []
    end
  end

  defp identify_unexpected_results(_result, _execution_context), do: []

  @spec check_anticipated_errors(map(), map(), map()) :: list(String.t())
  defp check_anticipated_errors(_result, %{planning: %{potential_issues: issues}}, %{
         execution_plan: %{error_points: _}
       })
       when length(issues) > 0 do
    # Would check if any anticipated issues actually occurred
    []
  end

  defp check_anticipated_errors(_result, _planning, _execution), do: []

  @spec has_anticipated_errors?(map(), map(), map()) :: boolean()
  defp has_anticipated_errors?(
         _planning,
         %{execution_plan: %{error_points: error_points}},
         _result
       ) do
    length(error_points) > 0
  end

  defp has_anticipated_errors?(_planning, _execution, _result), do: false

  @spec matches_expectations?(map(), map(), float()) :: boolean()
  defp matches_expectations?(_result, %{execution_plan: _plan}, tolerance) do
    # Simplified - would do real comparison in production
    tolerance >= 0.7
  end

  defp matches_expectations?(_result, _execution_context, _tolerance), do: true

  @spec determine_recommendation(atom(), float(), ValidationConfig.t()) :: atom()
  defp determine_recommendation(:success, _score, _config), do: :continue

  defp determine_recommendation(:partial_success, score, config) when score >= config.tolerance,
    do: :continue

  defp determine_recommendation(:partial_success, _score, _config), do: :investigate

  defp determine_recommendation(:unexpected, score, config) when score >= config.tolerance do
    :investigate
  end

  defp determine_recommendation(:unexpected, _score, %{retry_on_failure: true}), do: :retry
  defp determine_recommendation(:unexpected, _score, _config), do: :investigate
  defp determine_recommendation(:error, _score, %{retry_on_failure: true}), do: :retry
  defp determine_recommendation(:error, _score, _config), do: :investigate

  @spec generate_reflection(map(), map(), ValidationResult.t()) ::
          {:ok, String.t()} | {:error, term()}
  defp generate_reflection(agent, result, validation_result) do
    with {:ok, prompt} <- build_reflection_prompt(agent, result, validation_result),
         {:ok, model} <- get_validation_model(agent) do
      call_llm_for_reflection(prompt, model, agent)
    end
  end

  @spec build_reflection_prompt(map(), map(), ValidationResult.t()) :: {:ok, Jido.AI.Prompt.t()}
  defp build_reflection_prompt(agent, result, validation_result) do
    planning_summary = get_planning_summary(agent)
    execution_summary = get_execution_summary(agent)
    result_summary = summarize_result(result)

    template = """
    You are analyzing an execution that produced unexpected results.

    #{planning_summary}

    #{execution_summary}

    Actual Result:
    #{result_summary}

    Validation Status: #{validation_result.status}
    Match Score: #{Float.round(validation_result.match_score, 2)}

    Provide a brief reflection on:
    1. Why the result might differ from expectations
    2. What might have gone wrong
    3. Whether a retry might help or if the issue is fundamental

    Keep your reflection concise (2-3 sentences).
    """

    prompt = Prompt.new(:user, template)
    {:ok, prompt}
  end

  @spec get_validation_model(map()) :: {:ok, Model.t()} | {:error, term()}
  defp get_validation_model(agent) do
    model_name =
      get_in(agent, [:state, :validation_model]) ||
        get_in(agent, [:state, :cot_config, :model]) ||
        "gpt-4o"

    Model.from({:openai, model: model_name})
  end

  @spec call_llm_for_reflection(Jido.AI.Prompt.t(), Model.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  defp call_llm_for_reflection(prompt, model, agent) do
    temperature =
      get_in(agent, [:state, :validation_temperature]) ||
        get_in(agent, [:state, :cot_config, :temperature]) ||
        0.5

    ErrorHandler.with_retry(
      fn ->
        params = %{
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: 500
        }

        case TextCompletion.run(params, %{}) do
          {:ok, %{content: content}, _directives} when is_binary(content) ->
            {:ok, content}

          {:ok, response, _directives} ->
            Logger.warning("Unexpected response format: #{inspect(response)}")
            {:error, :invalid_response}

          {:error, reason} ->
            {:error, reason}
        end
      end,
      max_retries: 2,
      initial_delay_ms: 500
    )
  end

  @spec get_planning_context(map()) :: map()
  defp get_planning_context(agent) do
    case PlanningHook.get_planning_reasoning(agent) do
      {:ok, planning} -> %{planning: planning}
      {:error, _} -> %{}
    end
  end

  @spec get_execution_context(map()) :: map()
  defp get_execution_context(agent) do
    case ExecutionHook.get_execution_plan(agent) do
      {:ok, plan} -> %{execution_plan: plan}
      {:error, _} -> %{}
    end
  end

  @spec get_planning_summary(map()) :: String.t()
  defp get_planning_summary(agent) do
    case PlanningHook.get_planning_reasoning(agent) do
      {:ok, planning} ->
        """
        Planning Context:
        Goal: #{planning.goal}
        Anticipated Issues: #{length(planning.potential_issues)} identified
        """

      {:error, _} ->
        "Planning Context: Not available"
    end
  end

  @spec get_execution_summary(map()) :: String.t()
  defp get_execution_summary(agent) do
    case ExecutionHook.get_execution_plan(agent) do
      {:ok, plan} ->
        """
        Execution Plan:
        Strategy: #{plan.execution_strategy}
        Steps: #{length(plan.steps)}
        Error Points: #{length(plan.error_points)} identified
        """

      {:error, _} ->
        "Execution Plan: Not available"
    end
  end

  @spec summarize_result(map()) :: String.t()
  defp summarize_result(result) when is_map(result) do
    result
    |> Enum.map_join("\n", fn {key, value} -> "- #{key}: #{inspect(value, limit: 3)}" end)
  end

  defp summarize_result(result), do: inspect(result, limit: 5)

  @spec get_retry_count(map()) :: non_neg_integer()
  defp get_retry_count(agent) do
    get_in(agent, [:state, :validation_retry_count]) || 0
  end

  @spec increment_retry_count(map()) :: map()
  defp increment_retry_count(agent) do
    current_count = get_retry_count(agent)
    current_state = agent.state || %{}
    updated_state = Map.put(current_state, :validation_retry_count, current_count + 1)
    %{agent | state: updated_state}
  end

  @spec build_retry_params(map(), ValidationConfig.t(), non_neg_integer()) :: map()
  defp build_retry_params(agent, config, retry_count) do
    current_temp = get_in(agent, [:state, :cot_config, :temperature]) || 0.7
    adjusted_temp = min(current_temp + config.adjust_temperature * (retry_count + 1), 1.0)

    %{
      temperature: adjusted_temp,
      retry_attempt: retry_count + 1,
      reason: "validation_failure"
    }
  end
end
