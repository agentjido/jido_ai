defmodule Examples.ValidationHookAgent do
  @moduledoc """
  Example agent demonstrating Chain-of-Thought validation hook integration.

  This agent uses the `on_after_run/3` callback to validate execution results
  against planning expectations and execution plan, with support for automatic
  retry on validation failure.

  ## Usage

      # Create agent
      agent = Examples.ValidationHookAgent.new()

      # Enable validation CoT (enabled by default)
      agent = Jido.Agent.set(agent, :enable_validation_cot, true)

      # Configure validation behavior
      agent = Jido.Agent.set(agent, :validation_config, %{
        tolerance: 0.8,
        retry_on_failure: true,
        max_retries: 2,
        adjust_temperature: 0.1,
        generate_reflection: true
      })

      # Queue and run actions
      agent
      |> Jido.Agent.enqueue(SomeAction, %{})
      |> Jido.Agent.run()

      # Access validation result
      {:ok, validation} = Jido.AI.Runner.ChainOfThought.ValidationHook.get_validation_result(agent)
      IO.puts(validation.status)
      IO.puts(validation.reflection)

  ## Features

  - Post-execution validation against planning and execution context
  - Result matching with configurable tolerance
  - Unexpected result detection and reflection
  - Automatic retry on validation failure
  - Opt-in/opt-out via agent state flag
  - Graceful degradation on LLM failures
  """

  use Jido.Agent,
    name: "validation_hook_agent",
    actions: [],
    schema: []

  alias Jido.AI.Runner.ChainOfThought.{PlanningHook, ExecutionHook, ValidationHook}

  @doc """
  Planning hook - generates strategic reasoning before instructions are queued.

  This provides context for validation by setting expectations.
  """
  @impl Jido.Agent
  def on_before_plan(agent, instructions, context) do
    PlanningHook.generate_planning_reasoning(agent, instructions, context)
  end

  @doc """
  Execution hook - analyzes pending instructions before execution.

  This creates an execution plan that validation hook can compare against.
  """
  @impl Jido.Agent
  def on_before_run(agent) do
    ExecutionHook.generate_execution_plan(agent)
  end

  @doc """
  Validation hook callback - validates execution results.

  This is called automatically by Jido after the runner executes instructions.
  It validates results against:
  - Planning goals and anticipated issues
  - Execution plan expectations
  - Expected vs actual outcomes

  ## Implementation

  Uses `ValidationHook.validate_execution/3` to:
  - Compare results to expectations
  - Identify unexpected outcomes
  - Generate reflection on failures
  - Recommend retry if configured

  ## Opt-in Behavior

  Validation CoT is enabled by default but can be controlled via agent state:
  - `enable_validation_cot: true` - Perform validation (default)
  - `enable_validation_cot: false` - Skip validation

  ## Retry Support

  If validation fails and retry is configured, returns `{:retry, agent, params}`
  which signals the runner to retry execution with adjusted parameters.

  ## Returns

  - `{:ok, agent}` - Validation passed or disabled
  - `{:retry, agent, params}` - Validation failed, should retry (if configured)
  - `{:error, reason}` - Fatal validation error
  """
  @impl Jido.Agent
  def on_after_run(agent, result, unapplied_directives) do
    case ValidationHook.validate_execution(agent, result, unapplied_directives) do
      {:ok, validated_agent} = success ->
        # Log validation result
        case ValidationHook.get_validation_result(validated_agent) do
          {:ok, validation} ->
            require Logger

            Logger.info("""
            Validation completed:
              Status: #{validation.status}
              Match Score: #{Float.round(validation.match_score, 2)}
              Unexpected Results: #{length(validation.unexpected_results)}
              Recommendation: #{validation.recommendation}
            """)

            if validation.reflection != "" do
              Logger.info("Reflection: #{validation.reflection}")
            end

          {:error, _} ->
            :ok
        end

        success

      {:retry, agent, params} ->
        require Logger
        Logger.warning("Validation recommends retry with params: #{inspect(params)}")
        {:retry, agent, params}

      {:error, reason} = error ->
        require Logger
        Logger.error("Validation failed: #{inspect(reason)}")
        error
    end
  end
end
