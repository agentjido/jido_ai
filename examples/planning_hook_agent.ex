defmodule Examples.PlanningHookAgent do
  @moduledoc """
  Example agent demonstrating Chain-of-Thought planning hook integration.

  This agent uses the `on_before_plan/3` callback to generate strategic
  planning reasoning before instructions are queued. The planning analysis
  includes dependency identification, risk assessment, and recommendations.

  ## Usage

      # Create agent
      agent = Examples.PlanningHookAgent.new()

      # Enable planning CoT (enabled by default)
      agent
      |> Examples.PlanningHookAgent.enqueue(SomeAction, %{}, context: %{enable_planning_cot: true})

      # Disable planning CoT
      agent
      |> Examples.PlanningHookAgent.enqueue(SomeAction, %{}, context: %{enable_planning_cot: false})

      # Access planning reasoning
      {:ok, planning} = Jido.AI.Runner.ChainOfThought.PlanningHook.get_planning_reasoning(agent)
      IO.puts(planning.goal)
      IO.inspect(planning.dependencies)
      IO.inspect(planning.potential_issues)

  ## Features

  - Strategic planning analysis before instruction queuing
  - Dependency identification between instructions
  - Risk and issue detection
  - Optimization recommendations
  - Opt-in/opt-out via context flag
  - Graceful degradation on LLM failures
  """

  use Jido.Agent,
    name: "planning_hook_agent",
    actions: [],
    schema: []

  alias Jido.AI.Runner.ChainOfThought.PlanningHook

  @doc """
  Planning hook callback - generates strategic reasoning before instructions are queued.

  This is called automatically by Jido before instructions are added to the queue.
  It generates high-level planning reasoning that can be used by downstream hooks.

  ## Implementation

  Uses `PlanningHook.generate_planning_reasoning/3` to:
  - Analyze instruction intent and dependencies
  - Identify potential issues and risks
  - Provide optimization recommendations
  - Enrich agent context for downstream hooks

  ## Opt-in Behavior

  Planning CoT is enabled by default but can be controlled via context:
  - `enable_planning_cot: true` - Generate planning reasoning (default)
  - `enable_planning_cot: false` - Skip planning reasoning

  ## Returns

  - `{:ok, agent}` - Agent with planning reasoning in state (if enabled)
  - `{:ok, agent}` - Agent unchanged (if disabled or on error)
  """
  @impl Jido.Agent
  def on_before_plan(agent, instructions, context) do
    PlanningHook.generate_planning_reasoning(agent, instructions, context)
  end

  @doc """
  Optional: Execution hook that can access planning reasoning.

  This demonstrates how planning reasoning from `on_before_plan` can be
  accessed in downstream hooks for execution analysis.
  """
  @impl Jido.Agent
  def on_before_run(agent) do
    case PlanningHook.get_planning_reasoning(agent) do
      {:ok, planning} ->
        require Logger

        Logger.info("""
        Executing with planning context:
          Goal: #{planning.goal}
          Dependencies: #{length(planning.dependencies)}
          Issues: #{length(planning.potential_issues)}
        """)

        {:ok, agent}

      {:error, _} ->
        {:ok, agent}
    end
  end

  @doc """
  Optional: Validation hook that can use planning reasoning.

  This demonstrates how planning reasoning can inform post-execution validation.
  """
  @impl Jido.Agent
  def on_after_run(agent, result, unapplied_directives) do
    case PlanningHook.get_planning_reasoning(agent) do
      {:ok, planning} ->
        require Logger

        # Could validate result against planning expectations
        if length(planning.potential_issues) > 0 do
          Logger.info("Execution completed. Checking for anticipated issues...")
        end

        {:ok, agent}

      {:error, _} ->
        {:ok, agent}
    end
  end
end
