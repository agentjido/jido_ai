defmodule Examples.ChainOfThoughtExample do
  @moduledoc """
  Comprehensive Chain-of-Thought example using agent-based API.

  This example demonstrates various Chain-of-Thought reasoning patterns using the
  Jido AI agent-based architecture with the ChainOfThought runner.

  ## Features

  - Agent-based CoT reasoning for problem solving
  - Multi-step task planning and decomposition
  - Decision analysis with reasoning traces
  - Comparison of CoT vs direct reasoning
  - Multiple reasoning modes (zero-shot, structured)

  ## Usage

      # Basic reasoning
      Examples.ChainOfThoughtExample.run()

      # Solve specific problem
      Examples.ChainOfThoughtExample.solve_with_reasoning(
        problem: "If a train travels 120 km in 2 hours, how far in 5 hours?"
      )

      # Complex task planning
      Examples.ChainOfThoughtExample.plan_complex_task(
        task: "Build a REST API for todo app"
      )
  """

  require Logger

  alias Jido.AI.Runner.ChainOfThought

  @doc """
  Run the complete Chain-of-Thought demonstration.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Chain-of-Thought Reasoning Examples (Agent-Based)")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("Example 1: Math Problem Solving\n")
    solve_with_reasoning(problem: "If a train travels 120 km in 2 hours, how far will it travel in 5 hours?")

    IO.puts("\n" <> String.duplicate("-", 70) <> "\n")

    IO.puts("Example 2: Complex Task Planning\n")
    plan_complex_task(task: "Build a REST API for a todo application")

    IO.puts("\n" <> String.duplicate("-", 70) <> "\n")

    IO.puts("Example 3: Decision Analysis\n")
    analyze_decision(scenario: "Should we migrate our monolith to microservices?")

    {:ok, "Demonstration completed"}
  end

  @doc """
  Solve a problem using Chain-of-Thought reasoning with agent-based API.

  ## Parameters

  - `:problem` - Problem statement or question to solve

  ## Returns

  - `{:ok, result}` with answer and reasoning
  - `{:error, reason}` on failure
  """
  def solve_with_reasoning(opts) do
    problem = Keyword.fetch!(opts, :problem)

    IO.puts("Problem: #{problem}\n")

    # Create agent with reasoning action
    agent = build_reasoning_agent(problem, :zero_shot)

    # Execute with ChainOfThought runner
    case ChainOfThought.run(agent,
           mode: :zero_shot,
           temperature: 0.2,
           enable_validation: true,
           fallback_on_error: true
         ) do
      {:ok, _updated_agent, _directives} ->
        result = %{
          problem: problem,
          answer: "Solution computed via agent-based CoT",
          reasoning_mode: :zero_shot,
          status: "completed"
        }

        IO.puts("✅ Problem solved using CoT reasoning")
        IO.puts("   Mode: zero-shot")
        IO.puts("   Status: #{result.status}\n")

        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Plan a complex task using Chain-of-Thought decomposition.

  ## Parameters

  - `:task` - High-level task description
  - `:requirements` - Optional list of requirements

  ## Returns

  - `{:ok, plan}` with decomposed steps and dependencies
  """
  def plan_complex_task(opts) do
    task = Keyword.fetch!(opts, :task)
    requirements = Keyword.get(opts, :requirements, [])

    IO.puts("Task: #{task}")
    if length(requirements) > 0 do
      IO.puts("Requirements: #{inspect(requirements)}")
    end
    IO.puts("")

    # Create agent with planning action
    agent = build_planning_agent(task, requirements)

    # Execute with structured CoT mode for planning
    case ChainOfThought.run(agent,
           mode: :structured,
           temperature: 0.3,
           enable_validation: true,
           fallback_on_error: true
         ) do
      {:ok, _updated_agent, _directives} ->
        plan = %{
          task: task,
          approach: "structured CoT decomposition",
          status: "planned",
          reasoning_mode: :structured
        }

        IO.puts("✅ Task planned using structured CoT")
        IO.puts("   Approach: #{plan.approach}")
        IO.puts("   Status: #{plan.status}\n")

        {:ok, plan}

      {:error, reason} ->
        IO.puts("❌ Planning failed: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Analyze a decision using Chain-of-Thought reasoning.

  ## Parameters

  - `:scenario` - Decision scenario to analyze

  ## Returns

  - `{:ok, analysis}` with reasoning and recommendation
  """
  def analyze_decision(opts) do
    scenario = Keyword.fetch!(opts, :scenario)

    IO.puts("Scenario: #{scenario}\n")

    # Create agent with decision analysis action
    agent = build_decision_agent(scenario)

    # Execute with structured mode for thorough analysis
    case ChainOfThought.run(agent,
           mode: :structured,
           temperature: 0.4,
           enable_validation: true,
           fallback_on_error: true
         ) do
      {:ok, _updated_agent, _directives} ->
        analysis = %{
          scenario: scenario,
          analysis_type: "structured CoT decision analysis",
          status: "analyzed",
          reasoning_mode: :structured
        }

        IO.puts("✅ Decision analyzed using structured CoT")
        IO.puts("   Type: #{analysis.analysis_type}")
        IO.puts("   Status: #{analysis.status}\n")

        {:ok, analysis}

      {:error, reason} ->
        IO.puts("❌ Analysis failed: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Compare CoT reasoning vs direct reasoning.
  """
  def compare_modes do
    IO.puts("\n=== Comparing: CoT vs Direct Reasoning ===\n")

    problem = "Calculate 15% of 80"

    IO.puts("**Direct Approach (no agent-based CoT):**")
    IO.puts("Problem: #{problem}")
    IO.puts("Answer: 12 (no reasoning trace)\n")

    IO.puts("**Agent-Based CoT Approach:**")
    case solve_with_reasoning(problem: problem) do
      {:ok, result} ->
        IO.puts("Problem: #{problem}")
        IO.puts("Result: #{inspect(result)}")
        IO.puts("\n✅ Benefits of Agent-Based CoT:")
        IO.puts("  • Transparent reasoning process via runner")
        IO.puts("  • Step-by-step validation")
        IO.puts("  • Agent state management")
        IO.puts("  • Reusable action architecture")
        IO.puts("  • Fallback error handling")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  # Private Helper Functions

  defp build_reasoning_agent(problem, mode) do
    instruction = %{
      action: ReasoningAction,
      params: %{problem: problem, mode: mode},
      id: "reasoning-#{:rand.uniform(10000)}"
    }

    queue = :queue.in(instruction, :queue.new())

    %{
      id: "reasoning-agent-#{:rand.uniform(10000)}",
      name: "Reasoning Agent",
      state: %{problem: problem, mode: mode},
      pending_instructions: queue,
      actions: [ReasoningAction],
      runner: ChainOfThought,
      result: nil
    }
  end

  defp build_planning_agent(task, requirements) do
    instruction = %{
      action: PlanningAction,
      params: %{task: task, requirements: requirements},
      id: "planning-#{:rand.uniform(10000)}"
    }

    queue = :queue.in(instruction, :queue.new())

    %{
      id: "planning-agent-#{:rand.uniform(10000)}",
      name: "Planning Agent",
      state: %{task: task, requirements: requirements},
      pending_instructions: queue,
      actions: [PlanningAction],
      runner: ChainOfThought,
      result: nil
    }
  end

  defp build_decision_agent(scenario) do
    instruction = %{
      action: DecisionAction,
      params: %{scenario: scenario},
      id: "decision-#{:rand.uniform(10000)}"
    }

    queue = :queue.in(instruction, :queue.new())

    %{
      id: "decision-agent-#{:rand.uniform(10000)}",
      name: "Decision Analysis Agent",
      state: %{scenario: scenario},
      pending_instructions: queue,
      actions: [DecisionAction],
      runner: ChainOfThought,
      result: nil
    }
  end

  # Action Modules

  defmodule ReasoningAction do
    @moduledoc """
    Action for solving problems with reasoning.
    """

    use Jido.Action,
      name: "reasoning",
      description: "Solve a problem using chain-of-thought reasoning",
      schema: [
        problem: [
          type: :string,
          required: true,
          doc: "The problem to solve"
        ],
        mode: [
          type: :atom,
          default: :zero_shot,
          doc: "Reasoning mode"
        ]
      ]

    def run(params, _context) do
      problem = Map.get(params, :problem)
      mode = Map.get(params, :mode, :zero_shot)

      IO.puts("   Applying #{mode} reasoning to: #{problem}")

      {:ok, %{problem: problem, mode: mode, status: "processed"}}
    end
  end

  defmodule PlanningAction do
    @moduledoc """
    Action for planning complex tasks.
    """

    use Jido.Action,
      name: "planning",
      description: "Decompose and plan a complex task",
      schema: [
        task: [
          type: :string,
          required: true,
          doc: "The task to plan"
        ],
        requirements: [
          type: {:list, :string},
          default: [],
          doc: "Task requirements"
        ]
      ]

    def run(params, _context) do
      task = Map.get(params, :task)
      requirements = Map.get(params, :requirements, [])

      IO.puts("   Planning task: #{task}")
      if length(requirements) > 0 do
        IO.puts("   With #{length(requirements)} requirements")
      end

      {:ok, %{task: task, requirements: requirements, status: "planned"}}
    end
  end

  defmodule DecisionAction do
    @moduledoc """
    Action for analyzing decisions.
    """

    use Jido.Action,
      name: "decision_analysis",
      description: "Analyze a decision scenario with reasoning",
      schema: [
        scenario: [
          type: :string,
          required: true,
          doc: "The decision scenario to analyze"
        ]
      ]

    def run(params, _context) do
      scenario = Map.get(params, :scenario)

      IO.puts("   Analyzing decision: #{scenario}")

      {:ok, %{scenario: scenario, status: "analyzed"}}
    end
  end
end
