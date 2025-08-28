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
    config: [
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
    ]

  alias Jido.Tools.AI
  alias Jido.Signal
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
  def router(_opts) do
    [
      %{pattern: "jido.ai.generate.text", handler: &handle_generate_text/2},
      %{pattern: "jido.ai.generate.object", handler: &handle_generate_object/2},
      %{pattern: "jido.ai.stream.text", handler: &handle_stream_text/2},
      %{pattern: "jido.ai.stream.object", handler: &handle_stream_object/2},
      %{pattern: "jido.ai.model.status", handler: &handle_model_status/2}
    ]
  end

  @doc """
  Handles incoming AI-related signals and routes them to appropriate actions.
  """
  def handle_signal(%Signal{type: "jido.ai.generate.text"} = signal, skill) do
    params = merge_config_with_params(signal.data, skill)
    
    case AI.GenerateText.run(params, %{}) do
      {:ok, result} -> {:ok, %{signal | data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_signal(%Signal{type: "jido.ai.generate.object"} = signal, skill) do
    params = merge_config_with_params(signal.data, skill)
    
    case AI.GenerateObject.run(params, %{}) do
      {:ok, result} -> {:ok, %{signal | data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_signal(%Signal{type: "jido.ai.stream.text"} = signal, skill) do
    params = merge_config_with_params(signal.data, skill)
    
    case AI.StreamText.run(params, %{}) do
      {:ok, result} -> {:ok, %{signal | data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_signal(%Signal{type: "jido.ai.stream.object"} = signal, skill) do
    params = merge_config_with_params(signal.data, skill)
    
    case AI.StreamObject.run(params, %{}) do
      {:ok, result} -> {:ok, %{signal | data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_signal(%Signal{type: "jido.ai.model.status"} = signal, _skill) do
    # Return model status information
    status = %{
      available_models: ["gpt-4o", "gpt-4", "gpt-3.5-turbo"],
      status: :available,
      timestamp: DateTime.utc_now()
    }
    
    {:ok, %{signal | data: status}}
  end

  def handle_signal(signal, _skill) do
    Logger.warning("AI Skill received unhandled signal: #{signal.type}")
    {:ok, signal}
  end

  @doc """
  Transforms results from AI actions, adding metadata and formatting.
  """
  def transform_result(%Signal{type: "jido.ai.generate." <> _} = signal, result, _skill) do
    enhanced_result = Map.put(result, :skill_metadata, %{
      skill: "ai_skill",
      processed_at: DateTime.utc_now(),
      version: "1.0.0"
    })
    
    {:ok, enhanced_result}
  end

  def transform_result(%Signal{type: "jido.ai.stream." <> _} = signal, result, _skill) do
    enhanced_result = Map.put(result, :skill_metadata, %{
      skill: "ai_skill",
      processed_at: DateTime.utc_now(),
      version: "1.0.0",
      streaming: true
    })
    
    {:ok, enhanced_result}
  end

  def transform_result(_signal, result, _skill), do: {:ok, result}

  @doc """
  Mounts the AI skill to an agent, validating configuration.
  """
  def mount(agent, opts) do
    with {:ok, validated_opts} <- validate_opts(__MODULE__, opts) do
      # Store validated configuration in agent state
      updated_agent = put_in(agent.state[:skills][:ai], validated_opts)
      {:ok, updated_agent}
    end
  end

  # Private helper functions

  defp handle_generate_text(signal, skill) do
    handle_signal(%{signal | type: "jido.ai.generate.text"}, skill)
  end

  defp handle_generate_object(signal, skill) do
    handle_signal(%{signal | type: "jido.ai.generate.object"}, skill)
  end

  defp handle_stream_text(signal, skill) do
    handle_signal(%{signal | type: "jido.ai.stream.text"}, skill)
  end

  defp handle_stream_object(signal, skill) do
    handle_signal(%{signal | type: "jido.ai.stream.object"}, skill)
  end

  defp handle_model_status(signal, skill) do
    handle_signal(%{signal | type: "jido.ai.model.status"}, skill)
  end

  defp merge_config_with_params(params, %{opts_key: opts_key} = skill) do
    config = skill[opts_key] || %{}
    
    # Resolve default model if needed
    default_model = case config[:default_model] do
      nil -> "openai:gpt-4o"
      model_spec -> model_spec
    end
    
    params
    |> Map.put_new(:model, default_model)
    |> Map.put_new(:max_tokens, config[:max_tokens])
    |> Map.put_new(:temperature, config[:temperature])
  end
end
