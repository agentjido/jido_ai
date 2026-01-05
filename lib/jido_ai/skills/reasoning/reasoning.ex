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

  The skill uses `Jido.AI.Config.resolve_model/1` to resolve model aliases:

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
  Returns the skill specification with optional configuration.

  ## Configuration Options

  * `:default_model` - Default model alias to use (default: `:reasoning`)
  * `:default_max_tokens` - Default max tokens (default: `2048`)
  * `:default_temperature` - Default sampling temperature (default: `0.3`)

  ## Examples

      # Use all defaults
      spec = Jido.AI.Skills.Reasoning.skill_spec(%{})

      # Set custom defaults
      spec = Jido.AI.Skills.Reasoning.skill_spec(%{
        default_model: :capable,
        default_max_tokens: 4096
      })
  """
  def skill_spec(config) do
    %Jido.Skill.Spec{
      module: __MODULE__,
      name: name(),
      state_key: state_key(),
      description: description(),
      category: category(),
      vsn: vsn(),
      schema: schema(),
      config_schema: config_schema(),
      config: config,
      signal_patterns: signal_patterns(),
      tags: tags(),
      actions: actions()
    }
  end

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
end
