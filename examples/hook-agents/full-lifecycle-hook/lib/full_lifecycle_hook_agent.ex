defmodule Examples.FullLifecycleHookAgent do
  @moduledoc """
  Example agent demonstrating complete Chain-of-Thought lifecycle hook integration.

  This agent uses all three CoT lifecycle hooks:
  - `on_before_plan/3` - Strategic planning before queuing
  - `on_before_run/1` - Execution analysis before running
  - `on_after_run/3` - Validation after execution

  ## Usage

      # Create agent
      agent = Examples.FullLifecycleHookAgent.new()

      # Enable all CoT hooks (enabled by default)
      agent = agent
        |> Jido.Agent.set(:enable_planning_cot, true)
        |> Jido.Agent.set(:enable_execution_cot, true)

      # Queue some actions - planning hook analyzes
      agent = Jido.Agent.enqueue(agent, SomeAction, %{}, context: %{enable_planning_cot: true})

      # Run agent - execution hook analyzes, then executes, then validation
      {:ok, result_agent, directives} = Jido.Agent.run(agent)

      # Access planning and execution context
      {:ok, planning} = Jido.AI.Runner.ChainOfThought.PlanningHook.get_planning_reasoning(result_agent)
      {:ok, plan} = Jido.AI.Runner.ChainOfThought.ExecutionHook.get_execution_plan(result_agent)

  ## Features

  - Complete lifecycle CoT integration
  - Strategic planning → Execution analysis → Result validation
  - Planning context available to execution hook
  - Execution plan available to validation hook
  - Opt-in/opt-out for each hook independently
  - Graceful degradation at each stage
  """

  use Jido.Agent,
    name: "full_lifecycle_hook_agent",
    actions: [],
    schema: []

  alias Jido.AI.Runner.ChainOfThought.{PlanningHook, ExecutionHook, ValidationHook}

  @doc """
  Planning hook - generates strategic reasoning before instructions are queued.
  """
  @impl Jido.Agent
  def on_before_plan(agent, instructions, context) do
    PlanningHook.generate_planning_reasoning(agent, instructions, context)
  end

  @doc """
  Execution hook - analyzes pending instructions before execution.

  Has access to planning reasoning from on_before_plan for enhanced analysis.
  """
  @impl Jido.Agent
  def on_before_run(agent) do
    case ExecutionHook.generate_execution_plan(agent) do
      {:ok, updated_agent} = result ->
        # Log integration of planning and execution
        with {:ok, planning} <- PlanningHook.get_planning_reasoning(updated_agent),
             {:ok, plan} <- ExecutionHook.get_execution_plan(updated_agent) do
          require Logger

          Logger.info("""
          Lifecycle CoT Context:
            Planning Goal: #{planning.goal}
            Planning Dependencies: #{length(planning.dependencies)}
            Execution Strategy: #{plan.execution_strategy}
            Execution Steps: #{length(plan.steps)}
            Error Points: #{length(plan.error_points)}
          """)
        end

        result

      error ->
        error
    end
  end

  @doc """
  Validation hook - validates execution results against planning and execution context.

  Uses ValidationHook for comprehensive validation with automatic retry support.
  Has access to both planning reasoning and execution plan for validation.
  """
  @impl Jido.Agent
  def on_after_run(agent, result, unapplied_directives) do
    case ValidationHook.validate_execution(agent, result, unapplied_directives) do
      {:ok, validated_agent} = success ->
        require Logger

        # Log comprehensive validation results
        planning_result = PlanningHook.get_planning_reasoning(validated_agent)
        execution_result = ExecutionHook.get_execution_plan(validated_agent)
        validation_result = ValidationHook.get_validation_result(validated_agent)

        case {planning_result, execution_result, validation_result} do
          {{:ok, planning}, {:ok, plan}, {:ok, validation}} ->
            Logger.info("""
            Full Lifecycle Validation:
              Planning Goal: #{planning.goal}
              Anticipated Issues: #{length(planning.potential_issues)}
              Execution Steps: #{length(plan.steps)}
              Error Points: #{length(plan.error_points)}
              Validation Status: #{validation.status}
              Match Score: #{Float.round(validation.match_score, 2)}
              Recommendation: #{validation.recommendation}
            """)

            if validation.reflection != "" do
              Logger.info("Reflection: #{validation.reflection}")
            end

          _ ->
            Logger.debug("Validation completed with partial context")
        end

        success

      {:retry, agent, params} ->
        require Logger
        Logger.warning("Full lifecycle validation recommends retry: #{inspect(params)}")
        {:retry, agent, params}

      {:error, reason} = error ->
        require Logger
        Logger.error("Full lifecycle validation failed: #{inspect(reason)}")
        error
    end
  end
end
