defmodule Examples.ExecutionHookAgent do
  @moduledoc """
  Example agent demonstrating Chain-of-Thought execution hook integration.

  This agent uses the `on_before_run/1` callback to analyze pending instructions
  before execution, creating an execution plan with data flow dependencies and
  potential error points.

  ## Usage

      # Create agent
      agent = Examples.ExecutionHookAgent.new()

      # Enable execution CoT (enabled by default)
      agent = Jido.Agent.set(agent, :enable_execution_cot, true)

      # Disable execution CoT
      agent = Jido.Agent.set(agent, :enable_execution_cot, false)

      # Queue some actions
      agent
      |> Jido.Agent.enqueue(SomeAction, %{})
      |> Jido.Agent.enqueue(AnotherAction, %{})

      # Run agent - execution hook analyzes before running
      {:ok, result_agent, directives} = Jido.Agent.run(agent)

      # Access execution plan
      {:ok, plan} = Jido.AI.Runner.ChainOfThought.ExecutionHook.get_execution_plan(result_agent)
      IO.puts(plan.execution_strategy)
      IO.inspect(plan.steps)
      IO.inspect(plan.data_flow)
      IO.inspect(plan.error_points)

  ## Features

  - Execution-time analysis before instruction execution
  - Data flow dependency identification
  - Potential error point detection
  - Execution plan stored for post-execution validation
  - Opt-in/opt-out via agent state flag
  - Graceful degradation on LLM failures
  """

  use Jido.Agent,
    name: "execution_hook_agent",
    actions: [],
    schema: []

  alias Jido.AI.Runner.ChainOfThought.ExecutionHook

  @doc """
  Execution hook callback - analyzes pending instructions before execution.

  This is called automatically by Jido before the runner executes instructions.
  It generates an execution plan analyzing data flow, dependencies, and potential
  error points.

  ## Implementation

  Uses `ExecutionHook.generate_execution_plan/1` to:
  - Analyze pending instruction queue
  - Identify data flow between instructions
  - Detect potential error points
  - Create execution plan for validation
  - Enrich agent state for downstream hooks

  ## Opt-in Behavior

  Execution CoT is enabled by default but can be controlled via agent state:
  - `enable_execution_cot: true` - Generate execution plan (default)
  - `enable_execution_cot: false` - Skip execution analysis

  ## Returns

  - `{:ok, agent}` - Agent with execution plan in state (if enabled)
  - `{:ok, agent}` - Agent unchanged (if disabled or on error)
  """
  @impl Jido.Agent
  def on_before_run(agent) do
    ExecutionHook.generate_execution_plan(agent)
  end

  @doc """
  Optional: Post-execution validation using execution plan.

  This demonstrates how execution plan from `on_before_run` can be
  accessed in post-execution hooks for validation.
  """
  @impl Jido.Agent
  def on_after_run(agent, result, unapplied_directives) do
    case ExecutionHook.get_execution_plan(agent) do
      {:ok, plan} ->
        require Logger

        Logger.info("""
        Execution completed with plan:
          Strategy: #{plan.execution_strategy}
          Steps: #{length(plan.steps)}
          Data Flow: #{length(plan.data_flow)} dependencies
          Error Points: #{length(plan.error_points)} identified
        """)

        # Could validate result against plan expectations
        if length(plan.error_points) > 0 do
          Logger.info("Checking for anticipated error points...")
          # Custom validation logic here
        end

        {:ok, agent}

      {:error, _} ->
        {:ok, agent}
    end
  end
end
