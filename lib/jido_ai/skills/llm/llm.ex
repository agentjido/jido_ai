# Ensure actions are compiled before the skill
require Jido.AI.Skills.LLM.Actions.Chat
require Jido.AI.Skills.LLM.Actions.Complete
require Jido.AI.Skills.LLM.Actions.Embed

defmodule Jido.AI.Skills.LLM do
  @moduledoc """
  A Jido.Skill providing LLM capabilities for chat, completion, and embeddings.

  This skill wraps ReqLLM functionality into composable actions that can be
  attached to any Jido agent. It provides three core actions:

  * `Chat` - Chat-style interaction with optional system prompts
  * `Complete` - Simple text completion
  * `Embed` - Text embedding generation

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        skills: [
          {Jido.AI.Skills.LLM, []}
        ]
      end

  Or use the action directly:

      Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Chat, %{
        model: :fast,
        prompt: "What is Elixir?"
      })

  ## Model Resolution

  The skill uses `Jido.AI.Config.resolve_model/1` to resolve model aliases:

  * `:fast` - Quick model for simple tasks (default: `anthropic:claude-haiku-4-5`)
  * `:capable` - Capable model for complex tasks (default: `anthropic:claude-sonnet-4-20250514`)
  * `:reasoning` - Model for reasoning tasks (default: `anthropic:claude-sonnet-4-20250514`)

  Direct model specs are also supported (e.g., `"openai:gpt-4"`).

  ## Architecture Notes

  **Direct ReqLLM Calls**: This skill calls ReqLLM functions directly without
  any adapter layer, following the core design principle of Jido.AI.

  **Stateless**: The skill maintains no internal state - all configuration
  is passed via action parameters.
  """

  use Jido.Skill,
    name: "llm",
    state_key: :llm,
    actions: [
      Jido.AI.Skills.LLM.Actions.Chat,
      Jido.AI.Skills.LLM.Actions.Complete,
      Jido.AI.Skills.LLM.Actions.Embed
    ],
    description: "Provides LLM chat, completion, and embedding capabilities",
    category: "ai",
    tags: ["llm", "chat", "completion", "embeddings", "reqllm"],
    vsn: "1.0.0"

  @doc """
  Returns the skill specification with optional configuration.

  ## Configuration Options

  * `:default_model` - Default model alias to use (default: `:fast`)
  * `:default_max_tokens` - Default max tokens for generation (default: `1024`)
  * `:default_temperature` - Default sampling temperature (default: `0.7`)

  ## Examples

      # Use all defaults
      spec = Jido.AI.Skills.LLM.skill_spec(%{})

      # Set custom defaults
      spec = Jido.AI.Skills.LLM.skill_spec(%{
        default_model: :capable,
        default_max_tokens: 2048
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
      default_model: Map.get(config, :default_model, :fast),
      default_max_tokens: Map.get(config, :default_max_tokens, 1024),
      default_temperature: Map.get(config, :default_temperature, 0.7)
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for skill state.

  Defines the structure and defaults for LLM skill state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable, :reasoning)")
        |> Zoi.default(:fast),
      default_max_tokens:
        Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(1024),
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
      {"llm.chat", Jido.AI.Skills.LLM.Actions.Chat},
      {"llm.complete", Jido.AI.Skills.LLM.Actions.Complete},
      {"llm.embed", Jido.AI.Skills.LLM.Actions.Embed}
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
      "llm.chat",
      "llm.complete",
      "llm.embed"
    ]
  end
end
