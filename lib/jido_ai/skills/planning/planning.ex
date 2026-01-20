require Jido.AI.Skills.Planning.Actions.Decompose
# Ensure actions are compiled before the skill
require Jido.AI.Skills.Planning.Actions.Plan
require Jido.AI.Skills.Planning.Actions.Prioritize

defmodule Jido.AI.Skills.Planning do
  @moduledoc """
  A Jido.Skill providing AI-powered planning capabilities.

  This skill wraps ReqLLM functionality into composable actions that provide
  higher-level planning operations. It provides three core actions:

  * `Plan` - Generate structured plans from goals with constraints and resources
  * `Decompose` - Break down complex goals into hierarchical sub-goals
  * `Prioritize` - Order tasks by priority based on given criteria

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        skills: [
          {Jido.AI.Skills.Planning, []}
        ]
      end

  Or use the action directly:

      Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Plan, %{
        goal: "Build a web application",
        constraints: ["Must use Elixir", "Budget limited"],
        resources: ["2 developers", "3 months"]
      })

  ## Model Resolution

  The skill uses `Jido.AI.Config.resolve_model/1` to resolve model aliases:

  * `:fast` - Quick model for simple tasks
  * `:capable` - Capable model for complex tasks
  * `:planning` - Model optimized for planning (default: `anthropic:claude-sonnet-4-20250514`)

  Direct model specs are also supported.

  ## Architecture Notes

  **Direct ReqLLM Calls**: This skill calls ReqLLM functions directly without
  any adapter layer, following the core design principle of Jido.AI.

  **Specialized Prompts**: Each action uses a carefully crafted system prompt
  tailored to its specific planning task.

  **Stateless**: The skill maintains no internal state.
  """

  use Jido.Skill,
    name: "planning",
    state_key: :planning,
    actions: [
      Jido.AI.Skills.Planning.Actions.Plan,
      Jido.AI.Skills.Planning.Actions.Decompose,
      Jido.AI.Skills.Planning.Actions.Prioritize
    ],
    description: "Provides AI-powered planning, goal decomposition, and task prioritization",
    category: "ai",
    tags: ["planning", "decomposition", "prioritization", "ai"],
    vsn: "1.0.0"

  @doc """
  Initialize skill state when mounted to an agent.

  Returns initial state with any configured defaults.
  """
  @impl Jido.Skill
  def mount(_agent, config) do
    initial_state = %{
      default_model: Map.get(config, :default_model, :planning),
      default_max_tokens: Map.get(config, :default_max_tokens, 4096),
      default_temperature: Map.get(config, :default_temperature, 0.7)
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for skill state.

  Defines the structure and defaults for Planning skill state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable, :planning)")
        |> Zoi.default(:planning),
      default_max_tokens:
        Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(4096),
      default_temperature:
        Zoi.float(description: "Default sampling temperature (0.0-2.0)")
        |> Zoi.default(0.7)
    })
  end

  @doc """
  Returns the signal router for this skill.

  Maps signal patterns to action modules.
  """
  @impl Jido.Skill
  def router(_config) do
    [
      {"planning.plan", Jido.AI.Skills.Planning.Actions.Plan},
      {"planning.decompose", Jido.AI.Skills.Planning.Actions.Decompose},
      {"planning.prioritize", Jido.AI.Skills.Planning.Actions.Prioritize}
    ]
  end

  @doc """
  Pre-routing hook for incoming signals.

  Currently returns :continue to allow normal routing.
  """
  @impl Jido.Skill
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @doc """
  Transform the result returned from action execution.

  Currently passes through results unchanged.
  """
  @impl Jido.Skill
  def transform_result(_action, result, _context) do
    result
  end

  @doc """
  Returns signal patterns this skill responds to.
  """
  def signal_patterns do
    [
      "planning.plan",
      "planning.decompose",
      "planning.prioritize"
    ]
  end
end
