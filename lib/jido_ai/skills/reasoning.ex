# Ensure actions are compiled before the skill
require Jido.AI.Skills.Reasoning.Actions.Analyze
require Jido.AI.Skills.Reasoning.Actions.Explain
require Jido.AI.Skills.Reasoning.Actions.Infer

defmodule Jido.AI.Skills.Reasoning do
  @moduledoc """
  A Jido.Skill providing AI-powered reasoning capabilities.

  This skill wraps ReqLLM functionality into composable actions that provide
  higher-level reasoning operations beyond simple text generation. It provides
  three core actions:

  * `Analyze` - Deep analysis of text/data (sentiment, topics, entities, summary, custom)
  * `Infer` - Draw logical inferences from given premises
  * `Explain` - Get explanations for complex topics at different detail levels

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        skills: [
          {Jido.AI.Skills.Reasoning, []}
        ]
      end

  Or use the action directly:

      Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Analyze, %{
        input: "I loved the product!",
        analysis_type: :sentiment
      })

  ## Model Resolution

  The skill uses `Jido.AI.resolve_model/1` to resolve model aliases:

  * `:fast` - Quick model for simple tasks
  * `:capable` - Capable model for complex tasks
  * `:reasoning` - Model optimized for reasoning (default: `anthropic:claude-sonnet-4-20250514`)

  Direct model specs are also supported.

  ## Architecture Notes

  **Direct ReqLLM Calls**: This skill calls ReqLLM functions directly without
  any adapter layer, following the core design principle of Jido.AI.

  **Specialized Prompts**: Each action uses a carefully crafted system prompt
  tailored to its specific reasoning task.

  **Stateless**: The skill maintains no internal state.
  """

  use Jido.Skill,
    name: "reasoning",
    state_key: :reasoning,
    actions: [
      Jido.AI.Skills.Reasoning.Actions.Analyze,
      Jido.AI.Skills.Reasoning.Actions.Infer,
      Jido.AI.Skills.Reasoning.Actions.Explain
    ],
    description: "Provides AI-powered analysis, inference, and explanation capabilities",
    category: "ai",
    tags: ["reasoning", "analysis", "inference", "explanation", "ai"],
    vsn: "1.0.0"

  @doc """
  Initialize skill state when mounted to an agent.

  Returns initial state with any configured defaults.
  """
  @impl Jido.Skill
  def mount(_agent, config) do
    initial_state = %{
      default_model: Map.get(config, :default_model, :reasoning),
      default_max_tokens: Map.get(config, :default_max_tokens, 2048),
      default_temperature: Map.get(config, :default_temperature, 0.3)
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for skill state.

  Defines the structure and defaults for Reasoning skill state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable, :reasoning)")
        |> Zoi.default(:reasoning),
      default_max_tokens: Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(2048),
      default_temperature:
        Zoi.float(description: "Default sampling temperature (0.0-2.0)")
        |> Zoi.default(0.3)
    })
  end

  @doc """
  Returns the signal router for this skill.

  Maps signal patterns to action modules.
  """
  @impl Jido.Skill
  def router(_config) do
    [
      {"reasoning.analyze", Jido.AI.Skills.Reasoning.Actions.Analyze},
      {"reasoning.explain", Jido.AI.Skills.Reasoning.Actions.Explain},
      {"reasoning.infer", Jido.AI.Skills.Reasoning.Actions.Infer}
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
      "reasoning.analyze",
      "reasoning.explain",
      "reasoning.infer"
    ]
  end
end
