defmodule Jido.AI.Skill do
  @moduledoc """
  AI Skill providing text generation, streaming, and object creation capabilities.

  This skill integrates the core AI actions for Jido agents, following the standard
  Jido.Skill patterns and best practices. It provides a clean signal-based interface
  for AI operations with proper configuration validation, signal routing, and result
  transformation.

  ## Signal Patterns

  ### Incoming Requests
  - `jido.ai.generate_text` - Generate text responses
  - `jido.ai.generate_object` - Generate structured objects
  - `jido.ai.stream_text` - Stream text generation
  - `jido.ai.stream_object` - Stream object generation

  ### Outgoing Responses
  - `jido.ai.result` - Successful generation results
  - `jido.ai.stream_chunk` - Individual streaming chunks
  - `jido.ai.error` - Generation failures

  All outgoing signals include:
  - `request_id` - Links response to originating request
  - `operation` - The operation type (generate_text, stream_text, etc.)

  ## Configuration

  The skill accepts the following options:
  - `default_model`: AI model specification (default: "openai:gpt-4o")
  - `max_tokens`: Maximum tokens for generation (default: 1000)
  - `temperature`: Generation temperature 0.0-2.0 (default: 0.7)
  - `provider_config`: Provider-specific configuration map

  ## Usage Example

      agent = Agent.new("ai_agent")
      |> Agent.add_skill(Jido.AI.Skill, 
          default_model: "openai:gpt-4o",
          max_tokens: 2000,
          temperature: 0.8
        )

      # Send a generation signal
      signal = Signal.new(
        type: "jido.ai.generate_text",
        data: %{
          messages: "Hello, how are you?",
          max_tokens: 100
        }
      )

      Agent.handle_signal(agent, signal)
  """

  use Jido.Skill,
    name: "ai",
    description: "Provides AI text generation, streaming, and object creation capabilities",
    category: "ai",
    tags: ["ai", "generation", "llm", "text", "objects", "streaming"],
    vsn: "1.0.0",
    opts_key: :ai,
    opts_schema: [
      default_model: [
        type: :string,
        default: "openai:gpt-4o",
        doc: "Default AI model specification (provider:model format)"
      ],
      max_tokens: [
        type: :pos_integer,
        default: 1000,
        doc: "Default maximum tokens for generation"
      ],
      temperature: [
        type: {:custom, Jido.AI.Util, :validate_temperature, []},
        default: 0.7,
        doc: "Default temperature for generation (0.0-2.0)"
      ],
      system_prompt: [
        type: {:or, [:string, nil]},
        doc: "Default system prompt for generation"
      ],
      actions: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: [],
        doc: "List of Jido Action modules for tools"
      ],
      provider_config: [
        type: :map,
        default: %{},
        doc: "Provider-specific configuration options"
      ]
    ],
    signal_patterns: [
      "jido.ai.*"
    ],
    actions: [
      Jido.Tools.AI.GenerateText,
      Jido.Tools.AI.GenerateObject,
      Jido.Tools.AI.StreamText,
      Jido.Tools.AI.StreamObject
    ]

  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router.Route
  alias Jido.Tools.AI.GenerateObject
  alias Jido.Tools.AI.GenerateText
  alias Jido.Tools.AI.StreamObject
  alias Jido.Tools.AI.StreamText

  require Logger

  # Helper to build route structs following Arithmetic skill pattern
  defp route(path, action) do
    %Route{
      path: path,
      target: %Instruction{action: action},
      priority: 0
    }
  end

  @doc """
  Signal routing configuration mapping AI signal patterns to actions.

  Following the Jido.Skills.Arithmetic pattern with proper Route structs.
  """
  @impl true
  @spec router(keyword()) :: [Route.t()]
  def router(_opts) do
    [
      route("jido.ai.generate_text", GenerateText),
      route("jido.ai.generate_object", GenerateObject),
      route("jido.ai.stream_text", StreamText),
      route("jido.ai.stream_object", StreamObject)
    ]
  end

  @doc """
  Enriches incoming signals with default configuration and operation metadata.

  This follows the Arithmetic skill pattern - minimal signal enrichment only,
  leaving the actual business logic to the actions.
  """
  @impl true
  @spec handle_signal(Signal.t(), Jido.Skill.t()) :: {:ok, Signal.t()}
  def handle_signal(%Signal{} = signal, skill) do
    # Extract operation from signal type (jido.ai.generate_text -> generate_text)
    operation =
      signal.type
      |> String.split(".")
      # Remove "jido.ai" prefix
      |> Enum.drop(2)
      |> Enum.join("_")
      |> String.to_atom()

    # Enrich signal data with defaults and metadata
    provider_config = skill.ai[:provider_config] || %{}
    
    enriched_data =
      signal.data
      |> Map.put_new(:model, skill.ai[:default_model])
      |> Map.put_new(:max_tokens, skill.ai[:max_tokens])
      |> Map.put_new(:temperature, skill.ai[:temperature])
      |> Map.merge(provider_config)
      |> Map.put(:operation, operation)

    enriched_signal = %{signal | data: enriched_data}
    {:ok, enriched_signal}
  end

  @doc """
  Transforms action results into proper outgoing signals.

  Following Arithmetic skill pattern, creates new signals for results and errors
  with proper correlation metadata.
  """
  @impl true
  @spec transform_result(Signal.t(), {:ok, map()} | {:error, term()}, Jido.Skill.t()) ::
          {:ok, Signal.t()}
  def transform_result(%Signal{} = request, {:ok, result}, _skill) do
    # Determine output signal type based on operation
    output_type = determine_result_type(request.type, result)

    # Create result signal with correlation metadata
    result_signal = %Signal{
      id: Jido.Util.generate_id(),
      source: request.source,
      type: output_type,
      data:
        Map.merge(result, %{
          request_id: request.id,
          operation: Map.get(result, :operation, request.data[:operation])
        })
    }

    {:ok, result_signal}
  end

  def transform_result(%Signal{} = request, {:error, reason}, _skill) do
    # Create error signal with correlation metadata
    error_signal = %Signal{
      id: Jido.Util.generate_id(),
      source: request.source,
      type: "jido.ai.error",
      data: %{
        error: reason,
        request_id: request.id,
        operation: request.data[:operation]
      }
    }

    {:ok, error_signal}
  end

  # Private helpers

  # Determine the appropriate result signal type
  defp determine_result_type("jido.ai.stream_" <> _, %{stream: _}), do: "jido.ai.stream_chunk"
  defp determine_result_type("jido.ai.stream_" <> _, _), do: "jido.ai.stream_done"
  defp determine_result_type(_, _), do: "jido.ai.result"
end
