defmodule Jido.AI.Skill do
  @moduledoc """
  An AI skill that provides text generation, streaming, and object creation capabilities
  to Jido agents.

  This skill integrates the core AI actions (generateText, streamText, generateObject,
  streamObject) and handles AI-related signal patterns for agent communication.

  ## Signal Patterns

  This skill handles the following signal patterns:
  - `jido.ai.generate.*` - Text and object generation requests
  - `jido.ai.stream.*` - Streaming generation requests
  - `jido.ai.model.*` - Model configuration and status signals

  ## Configuration

  The skill accepts the following configuration options:
  - `default_model`: Default AI model specification (default: "openai:gpt-4o")
  - `max_tokens`: Default maximum tokens (default: 1000)
  - `temperature`: Default temperature (default: 0.7)
  - `provider_config`: Provider-specific configuration

  ## Usage Example

      agent = Agent.new("my_agent")
      |> Agent.add_skill(Jido.AI.Skill,
          default_model: "openai:gpt-4o",
          max_tokens: 2000,
          temperature: 0.8
        )
  """

  use Jido.Skill,
    name: "ai_skill",
    description: "Provides AI text generation, streaming, and object creation capabilities",
    category: "ai",
    tags: ["ai", "generation", "text", "objects", "streaming"],
    vsn: "1.0.0",
    opts_key: :ai,
    signal_patterns: [
      "jido.ai.*"
    ],
    opts_schema: [
      default_model: [
        type: :any,
        default: "openai:gpt-4o",
        doc: "Default AI model specification (string, tuple, or Model struct)"
      ],
      max_tokens: [
        type: :pos_integer,
        default: 1000,
        doc: "Default maximum tokens for generation"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Default temperature for generation (0.0-2.0)"
      ],
      provider_config: [
        type: :map,
        default: %{},
        doc: "Provider-specific configuration"
      ]
    ],
    actions: [
      Jido.Tools.AI.GenerateText,
      Jido.Tools.AI.GenerateObject,
      Jido.Tools.AI.StreamText,
      Jido.Tools.AI.StreamObject
    ]

  alias Jido.Signal
  alias Jido.Instruction

  require Logger

  @doc """
  Child process specifications for the AI skill.

  Currently returns an empty list as the AI actions don't require
  persistent child processes. This may change if we add connection
  pooling or other stateful components.
  """
  def child_spec(_config), do: []

  @doc """
  Signal routing configuration for AI-related patterns.
  """
  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.ai.generate.text",
        target: %Instruction{action: Jido.Tools.AI.GenerateText},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.ai.generate.object",
        target: %Instruction{action: Jido.Tools.AI.GenerateObject},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.ai.stream.text",
        target: %Instruction{action: Jido.Tools.AI.StreamText},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.ai.stream.object",
        target: %Instruction{action: Jido.Tools.AI.StreamObject},
        priority: 0
      }
    ]
  end

  @doc """
  Handle an AI signal, adding configuration defaults.
  """
  @impl true
  @spec handle_signal(Signal.t(), Jido.Skill.t()) :: {:ok, Signal.t()}
  def handle_signal(%Signal{} = signal, skill) do
    params = merge_config_with_params(signal.data, skill)
    {:ok, %{signal | data: params}}
  end

  @doc """
  Process the result of an AI operation, adding metadata.
  """
  @impl true
  @spec transform_result(Signal.t(), {:ok, map()} | {:error, String.t()}, Jido.Skill.t()) ::
          {:ok, Signal.t()}
  def transform_result(%Signal{type: "jido.ai.generate." <> _} = signal, {:ok, result}, skill) do
    enhanced_result =
      Map.put(result, :skill_metadata, %{
        skill: "ai_skill",
        processed_at: DateTime.utc_now(),
        version: "1.0.0"
      })

    {:ok, %{signal | data: enhanced_result}}
  end

  def transform_result(%Signal{type: "jido.ai.stream." <> _} = signal, {:ok, result}, skill) do
    enhanced_result =
      Map.put(result, :skill_metadata, %{
        skill: "ai_skill",
        processed_at: DateTime.utc_now(),
        version: "1.0.0",
        streaming: true
      })

    {:ok, %{signal | data: enhanced_result}}
  end

  def transform_result(%Signal{} = signal, {:error, error}, _skill) do
    {:ok,
     %Signal{
       id: Jido.Util.generate_id(),
       source: signal.source,
       type: "jido.ai.error",
       data: %{
         error: error,
         original_signal: signal.type
       }
     }}
  end

  def transform_result(_signal, result, _skill), do: {:ok, result}

  @doc """
  Mounts the AI skill to an agent, validating configuration.
  """
  def mount(agent, opts) do
    with {:ok, validated_opts} <- Jido.Skill.validate_opts(__MODULE__, opts) do
      # Store validated configuration in agent state
      updated_agent = put_in(agent.state[:skills][:ai], validated_opts)
      {:ok, updated_agent}
    end
  end

  # Private helper functions

  defp merge_config_with_params(params, %{opts_key: opts_key} = skill) do
    config = skill[opts_key] || %{}

    # Resolve default model if needed
    default_model =
      case config[:default_model] do
        nil -> "openai:gpt-4o"
        model_spec -> model_spec
      end

    params
    |> Map.put_new(:model, default_model)
    |> Map.put_new(:max_tokens, config[:max_tokens])
    |> Map.put_new(:temperature, config[:temperature])
  end
end
