# Ensure actions are compiled before the plugin
require Jido.AI.Actions.LLM.Chat
require Jido.AI.Actions.LLM.Complete
require Jido.AI.Actions.LLM.Embed
require Jido.AI.Actions.LLM.GenerateObject

defmodule Jido.AI.Plugins.LLM do
  @moduledoc """
  A Jido.Plugin providing LLM capabilities for chat, completion, and embeddings.

  This plugin wraps ReqLLM functionality into composable actions that can be
  attached to any Jido agent. It provides three core actions:

  * `Chat` - Chat-style interaction with optional system prompts
  * `Complete` - Simple text completion
  * `Embed` - Text embedding generation

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        plugins: [
          {Jido.AI.Plugins.LLM, []}
        ]
      end

  Or use the action directly:

      Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        model: :fast,
        prompt: "What is Elixir?"
      })

  ## Model Resolution

  The plugin uses `Jido.AI.resolve_model/1` to resolve model aliases:

  * `:fast` - Quick model for simple tasks (default: `anthropic:claude-haiku-4-5`)
  * `:capable` - Capable model for complex tasks (default: `anthropic:claude-sonnet-4-20250514`)
  * `:reasoning` - Model for reasoning tasks (default: `anthropic:claude-sonnet-4-20250514`)

  Direct model specs are also supported (e.g., `"openai:gpt-4"`).

  ## Architecture Notes

  **Direct ReqLLM Calls**: This plugin calls ReqLLM functions directly without
  any adapter layer, following the core design principle of Jido.AI.

  **Stateless**: The plugin maintains no internal state - all configuration
  is passed via action parameters.
  """

  use Jido.Plugin,
    name: "llm",
    state_key: :llm,
    actions: [
      Jido.AI.Actions.LLM.Chat,
      Jido.AI.Actions.LLM.Complete,
      Jido.AI.Actions.LLM.Embed,
      Jido.AI.Actions.LLM.GenerateObject
    ],
    description: "Provides LLM chat, completion, and embedding capabilities",
    category: "ai",
    tags: ["llm", "chat", "completion", "embeddings", "reqllm"],
    vsn: "1.0.0"

  @doc """
  Initialize plugin state when mounted to an agent.

  Returns initial state with any configured defaults.
  """
  @impl Jido.Plugin
  def mount(_agent, config) do
    initial_state = %{
      default_model: Map.get(config, :default_model, :fast),
      default_max_tokens: Map.get(config, :default_max_tokens, 1024),
      default_temperature: Map.get(config, :default_temperature, 0.7)
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for plugin state.

  Defines the structure and defaults for LLM plugin state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable, :reasoning)")
        |> Zoi.default(:fast),
      default_max_tokens: Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(1024),
      default_temperature:
        Zoi.float(description: "Default sampling temperature (0.0-2.0)")
        |> Zoi.default(0.7)
    })
  end

  @doc """
  Returns the signal router for this plugin.

  Maps signal patterns to action modules.
  """
  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"llm.chat", Jido.AI.Actions.LLM.Chat},
      {"llm.complete", Jido.AI.Actions.LLM.Complete},
      {"llm.embed", Jido.AI.Actions.LLM.Embed},
      {"llm.generate_object", Jido.AI.Actions.LLM.GenerateObject}
    ]
  end

  @doc """
  Pre-routing hook for incoming signals.

  Currently returns :continue to allow normal routing.
  """
  @impl Jido.Plugin
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @doc """
  Transform the result returned from action execution.

  Currently passes through results unchanged.
  """
  @impl Jido.Plugin
  def transform_result(_action, result, _context) do
    result
  end

  @doc """
  Returns signal patterns this plugin responds to.
  """
  def signal_patterns do
    [
      "llm.chat",
      "llm.complete",
      "llm.embed",
      "llm.generate_object"
    ]
  end
end
