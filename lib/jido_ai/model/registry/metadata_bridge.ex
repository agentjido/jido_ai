defmodule Jido.AI.Model.Registry.MetadataBridge do
  @moduledoc """
  Converts between ReqLLM and Jido AI model formats.

  This module provides the essential translation layer between ReqLLM's model
  format and Jido AI's expected model structure, ensuring 100% backward
  compatibility while enabling access to ReqLLM's rich metadata.

  ## Key Responsibilities

  - Convert ReqLLM.Model structs to Jido.AI.Model structs
  - Preserve all existing Jido AI model fields and structure
  - Enhance models with ReqLLM capabilities, pricing, and limits
  - Handle missing or incompatible metadata gracefully
  - Maintain consistent model identification and naming

  ## Format Compatibility

  The bridge ensures that all existing Jido AI code continues working by:
  - Preserving model.id, model.name, model.provider fields
  - Converting ReqLLM endpoints to Jido AI endpoint format
  - Translating capabilities, modalities, and pricing information
  - Setting appropriate defaults for missing fields
  """

  require Logger
  alias Jido.AI.Model
  alias Jido.AI.Model.{Architecture, Endpoint, Pricing}

  @type reqllm_model :: ReqLLM.Model.t()
  @type jido_model :: Jido.AI.Model.t()

  @doc """
  Converts a ReqLLM.Model struct to Jido.AI.Model format.

  This is the primary conversion function that transforms ReqLLM models
  into the format expected by existing Jido AI applications.

  ## Parameters
    - reqllm_model: ReqLLM.Model struct from the registry

  ## Returns
    - Jido.AI.Model struct with enhanced metadata

  ## Examples

      reqllm_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        capabilities: %{tool_call: true, reasoning: true},
        limit: %{context: 200_000, output: 4_096}
      }

      jido_model = to_jido_model(reqllm_model)
      jido_model.provider # => :anthropic
      jido_model.id # => "claude-3-5-sonnet"
      jido_model.capabilities.tool_call # => true

  """
  @spec to_jido_model(reqllm_model()) :: jido_model()
  def to_jido_model(%ReqLLM.Model{} = reqllm_model) do
    # Generate ReqLLM ID for traceability
    reqllm_id = "#{reqllm_model.provider}:#{reqllm_model.model}"

    # Create base Jido AI model structure
    %Model{
      # Core identification
      id: reqllm_model.model,
      name: humanize_model_name(reqllm_model.model),
      provider: reqllm_model.provider,
      reqllm_id: reqllm_id,

      # Model metadata
      description: generate_model_description(reqllm_model),
      created: extract_creation_timestamp(reqllm_model),

      # Architecture information
      architecture: convert_architecture(reqllm_model),

      # Endpoint configuration
      endpoints: convert_endpoints(reqllm_model),

      # ReqLLM-specific enhancements
      base_url: get_provider_base_url(reqllm_model.provider),
      model: reqllm_model.model,

      # Runtime configuration with defaults
      temperature: 0.7,
      max_tokens: extract_max_tokens(reqllm_model),
      max_retries: reqllm_model.max_retries || 3,

      # Enhanced fields (may not exist in legacy models)
      capabilities: reqllm_model.capabilities,
      modalities: reqllm_model.modalities,
      cost: reqllm_model.cost
    }
  end

  @doc """
  Enhances an existing Jido AI model with ReqLLM registry data.

  This function allows existing Jido AI models to be enhanced with
  additional metadata from the ReqLLM registry without losing
  any existing information.

  ## Parameters
    - jido_model: Existing Jido.AI.Model struct
    - reqllm_metadata: Additional metadata from ReqLLM registry

  ## Returns
    - Enhanced Jido.AI.Model struct

  ## Examples

      existing_model = %Jido.AI.Model{id: "claude-3-5-sonnet", provider: :anthropic}
      registry_data = %{capabilities: %{tool_call: true}, limit: %{context: 200_000}}

      enhanced = enhance_with_registry_data(existing_model, registry_data)
      enhanced.capabilities.tool_call # => true

  """
  @spec enhance_with_registry_data(jido_model(), map()) :: jido_model()
  def enhance_with_registry_data(%Model{} = jido_model, reqllm_metadata)
      when is_map(reqllm_metadata) do
    # Update model with enhanced metadata, preserving existing fields
    jido_model
    |> maybe_update_field(:capabilities, reqllm_metadata[:capabilities])
    |> maybe_update_field(:modalities, reqllm_metadata[:modalities])
    |> maybe_update_field(:cost, reqllm_metadata[:cost])
    |> maybe_update_limit(reqllm_metadata[:limit])
    |> maybe_update_endpoints_from_limit(reqllm_metadata[:limit])
    |> set_reqllm_id_if_missing()
  end

  @doc """
  Converts Jido AI model format back to ReqLLM format.

  This reverse conversion is useful for passing Jido AI models
  to ReqLLM functions or for round-trip compatibility testing.

  ## Parameters
    - jido_model: Jido.AI.Model struct

  ## Returns
    - ReqLLM.Model struct

  ## Examples

      jido_model = %Jido.AI.Model{
        provider: :anthropic,
        id: "claude-3-5-sonnet",
        max_tokens: 4096
      }

      reqllm_model = to_reqllm_model(jido_model)
      reqllm_model.provider # => :anthropic
      reqllm_model.model # => "claude-3-5-sonnet"

  """
  @spec to_reqllm_model(jido_model()) :: reqllm_model()
  def to_reqllm_model(%Model{} = jido_model) do
    # Create ReqLLM model from Jido AI model
    base_model =
      ReqLLM.Model.new(
        jido_model.provider,
        jido_model.id || jido_model.model,
        max_tokens: jido_model.max_tokens,
        max_retries: jido_model.max_retries
      )

    # Enhance with additional fields if available
    %{
      base_model
      | capabilities: jido_model.capabilities,
        modalities: jido_model.modalities,
        cost: jido_model.cost,
        limit: extract_limit_from_endpoints(jido_model.endpoints)
    }
  end

  @doc """
  Validates model format compatibility between ReqLLM and Jido AI.

  Checks that a model can be safely converted between formats
  without losing essential information.

  ## Parameters
    - model: Either ReqLLM.Model or Jido.AI.Model struct

  ## Returns
    - {:ok, :compatible} if formats are compatible
    - {:error, reasons} if compatibility issues exist

  ## Examples

      validate_compatibility(reqllm_model) # => {:ok, :compatible}
      validate_compatibility(invalid_model) # => {:error, ["missing provider", "invalid model name"]}

  """
  @spec validate_compatibility(reqllm_model() | jido_model()) ::
          {:ok, :compatible} | {:error, [String.t()]}
  def validate_compatibility(%ReqLLM.Model{} = reqllm_model) do
    errors = []

    errors =
      if is_nil(reqllm_model.provider) or not is_atom(reqllm_model.provider) do
        ["Invalid provider: must be non-nil atom" | errors]
      else
        errors
      end

    errors =
      if is_nil(reqllm_model.model) or not is_binary(reqllm_model.model) or
           reqllm_model.model == "" do
        ["Invalid model name: must be non-empty string" | errors]
      else
        errors
      end

    case errors do
      [] -> {:ok, :compatible}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_compatibility(%Model{} = jido_model) do
    errors = []

    errors =
      if is_nil(jido_model.provider) or not is_atom(jido_model.provider) do
        ["Invalid provider: must be non-nil atom" | errors]
      else
        errors
      end

    model_id = jido_model.id || jido_model.model

    errors =
      if is_nil(model_id) or not is_binary(model_id) or model_id == "" do
        ["Invalid model identifier: must be non-empty string" | errors]
      else
        errors
      end

    case errors do
      [] -> {:ok, :compatible}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_compatibility(_), do: {:error, ["Unsupported model format"]}

  # Private helper functions

  defp humanize_model_name(model_name) when is_binary(model_name) do
    if String.contains?(model_name, ["-", "_"]) do
      # Only process names with separators
      model_name
      |> String.replace("-", " ")
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)
    else
      # Preserve names without separators unchanged
      model_name
    end
  end

  defp generate_model_description(%ReqLLM.Model{} = reqllm_model) do
    provider_name = reqllm_model.provider |> Atom.to_string() |> String.capitalize()
    model_name = humanize_model_name(reqllm_model.model)

    base_description = "#{provider_name} #{model_name} model"

    # Add capability information if available
    case reqllm_model.capabilities do
      nil ->
        base_description

      caps ->
        features = []
        features = if Map.get(caps, :reasoning), do: ["reasoning" | features], else: features
        features = if Map.get(caps, :tool_call), do: ["tool calling" | features], else: features

        features =
          if Map.get(caps, :attachment), do: ["file attachments" | features], else: features

        if Enum.empty?(features) do
          base_description
        else
          feature_text = Enum.join(features, ", ")
          "#{base_description} with #{feature_text} capabilities"
        end
    end
  end

  defp extract_creation_timestamp(_reqllm_model) do
    # ReqLLM models don't have creation timestamps
    # Use current time as placeholder
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp convert_architecture(%ReqLLM.Model{} = reqllm_model) do
    # Create architecture information from available metadata
    modalities = reqllm_model.modalities || %{input: [:text], output: [:text]}
    input_modalities = Map.get(modalities, :input, [:text])

    modality_str =
      if :text in input_modalities and length(input_modalities) > 1 do
        "multimodal"
      else
        "text"
      end

    %Architecture{
      modality: modality_str,
      tokenizer: infer_tokenizer(reqllm_model.provider),
      instruct_type: infer_instruct_type(reqllm_model)
    }
  end

  defp convert_endpoints(%ReqLLM.Model{} = reqllm_model) do
    # Convert ReqLLM limit information to Jido AI endpoint format
    case reqllm_model.limit do
      nil ->
        [create_default_endpoint(reqllm_model)]

      limit ->
        [create_endpoint_from_limit(reqllm_model, limit)]
    end
  end

  defp create_default_endpoint(%ReqLLM.Model{} = reqllm_model) do
    %Endpoint{
      name: reqllm_model.model,
      provider_name: Atom.to_string(reqllm_model.provider),
      # Conservative default
      context_length: 8192,
      max_completion_tokens: reqllm_model.max_tokens || 4096,
      max_prompt_tokens: nil,
      quantization: nil,
      supported_parameters: ["temperature", "max_tokens", "top_p"],
      pricing: convert_pricing(reqllm_model.cost)
    }
  end

  defp create_endpoint_from_limit(%ReqLLM.Model{} = reqllm_model, limit) do
    %Endpoint{
      name: reqllm_model.model,
      provider_name: Atom.to_string(reqllm_model.provider),
      context_length: get_limit_field(limit, :context) || 8192,
      max_completion_tokens: get_limit_field(limit, :output) || reqllm_model.max_tokens || 4096,
      max_prompt_tokens: nil,
      quantization: nil,
      supported_parameters: infer_supported_parameters(reqllm_model),
      pricing: convert_pricing(reqllm_model.cost)
    }
  end

  defp convert_pricing(nil), do: %Pricing{completion: nil, image: nil, prompt: nil, request: nil}

  defp convert_pricing(cost) when is_map(cost) do
    %Pricing{
      completion: format_cost(Map.get(cost, :output)),
      prompt: format_cost(Map.get(cost, :input)),
      # Most models don't have separate image pricing
      image: nil,
      request: nil
    }
  end

  defp format_cost(nil), do: nil

  defp format_cost(cost) when is_number(cost) do
    # Format cost per token as readable string avoiding scientific notation
    # Cost appears to be in thousandths, so multiply by 1000 to get the right scale
    cost_value = cost * 1_000
    # Ensure cost_value is a float for :erlang.float_to_binary
    cost_float = cost_value / 1
    formatted_cost = :erlang.float_to_binary(cost_float, decimals: 1)
    "$#{formatted_cost} / 1M tokens"
  end

  defp format_cost(cost) when is_binary(cost), do: cost

  defp extract_max_tokens(%ReqLLM.Model{} = reqllm_model) do
    reqllm_model.max_tokens ||
      (reqllm_model.limit && get_limit_field(reqllm_model.limit, :output)) ||
      1024
  end

  # Helper to safely access limit fields (limit can be a struct or a map)
  defp get_limit_field(limit, field) when is_map(limit) do
    Map.get(limit, field) || Map.get(limit, to_string(field))
  end

  defp get_limit_field(_, _), do: nil

  defp get_provider_base_url(provider) do
    # Map providers to their API base URLs
    case provider do
      :anthropic -> "https://api.anthropic.com"
      :openai -> "https://api.openai.com/v1"
      :google -> "https://generativelanguage.googleapis.com"
      :mistral -> "https://api.mistral.ai"
      :openrouter -> "https://openrouter.ai/api/v1"
      :groq -> "https://api.groq.com"
      :cohere -> "https://api.cohere.ai"
      _ -> nil
    end
  end

  defp infer_tokenizer(provider) do
    # Infer tokenizer based on provider
    case provider do
      :anthropic -> "claude"
      :openai -> "gpt"
      :google -> "gemini"
      :mistral -> "mistral"
      _ -> "unknown"
    end
  end

  defp infer_instruct_type(%ReqLLM.Model{} = reqllm_model) do
    # Infer instruction format based on model name
    model_name = String.downcase(reqllm_model.model)

    cond do
      String.contains?(model_name, "instruct") -> "instruct"
      String.contains?(model_name, "chat") -> "chat"
      reqllm_model.provider in [:anthropic, :openai] -> "chat"
      true -> "instruct"
    end
  end

  defp infer_supported_parameters(%ReqLLM.Model{} = reqllm_model) do
    base_params = ["max_tokens"]

    # Add temperature if supported
    params =
      if reqllm_model.capabilities && Map.get(reqllm_model.capabilities, :temperature, true) do
        ["temperature" | base_params]
      else
        base_params
      end

    # Add tool calling parameters if supported
    params =
      if reqllm_model.capabilities && Map.get(reqllm_model.capabilities, :tool_call, false) do
        ["tools", "tool_choice" | params]
      else
        params
      end

    # Add common parameters
    ["top_p", "top_k" | params] |> Enum.uniq()
  end

  defp maybe_update_field(model, _field, nil), do: model

  defp maybe_update_field(model, field, value) do
    Map.put(model, field, value)
  end

  defp maybe_update_limit(model, nil), do: model

  defp maybe_update_limit(model, limit) when is_map(limit) do
    # Store limit information in model for potential use
    # This is a custom field that may not exist in base Model struct
    Map.put(model, :limit, limit)
  end

  defp maybe_update_endpoints_from_limit(model, nil), do: model

  defp maybe_update_endpoints_from_limit(%{endpoints: nil} = model, limit) when is_map(limit) do
    # Create default endpoint if none exist
    alias Jido.AI.Model.Endpoint

    default_endpoint = %Endpoint{
      context_length: get_limit_field(limit, :context) || 8192,
      max_completion_tokens: get_limit_field(limit, :output) || 4096
    }

    %{model | endpoints: [default_endpoint]}
  end

  defp maybe_update_endpoints_from_limit(model, limit) when is_map(limit) do
    # Update existing endpoints
    updated_endpoints =
      model.endpoints
      |> Enum.map(fn endpoint ->
        %{
          endpoint
          | context_length: get_limit_field(limit, :context) || endpoint.context_length,
            max_completion_tokens:
              get_limit_field(limit, :output) || endpoint.max_completion_tokens
        }
      end)

    %{model | endpoints: updated_endpoints}
  end

  defp set_reqllm_id_if_missing(%Model{reqllm_id: nil} = model) do
    reqllm_id = "#{model.provider}:#{model.id || model.model}"
    %{model | reqllm_id: reqllm_id}
  end

  defp set_reqllm_id_if_missing(model), do: model

  defp extract_limit_from_endpoints(nil), do: nil
  defp extract_limit_from_endpoints([]), do: nil

  defp extract_limit_from_endpoints([endpoint | _]) do
    %{
      context: endpoint.context_length,
      output: endpoint.max_completion_tokens
    }
  end
end
