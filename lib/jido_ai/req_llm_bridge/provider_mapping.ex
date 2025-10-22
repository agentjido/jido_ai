defmodule Jido.AI.ReqLlmBridge.ProviderMapping do
  @moduledoc """
  Provider mapping functionality for ReqLLM integration.

  This module handles the mapping between Jido AI's provider system and ReqLLM's
  provider addressing scheme. It includes model name normalization, fallback
  mechanisms, and validation for ReqLLM model availability.
  """

  require Logger

  alias ReqLLM.Provider.Generated.ValidProviders

  # Maps Jido AI provider names to ReqLLM provider names.
  # Some providers may have different names in ReqLLM, so this mapping
  # ensures the correct provider identifier is used.
  @provider_mapping %{
    openai: :openai,
    anthropic: :anthropic,
    google: :google,
    openrouter: :openrouter,
    cloudflare: :cloudflare,
    mistral: :mistral
  }

  # Model name normalization rules for ReqLLM format requirements.
  # Some model names need to be normalized to match ReqLLM's expected format.
  @model_normalizations %{
    # OpenAI normalizations
    "gpt-4-turbo" => "gpt-4-turbo-preview",
    "gpt-4o" => "gpt-4o",
    "gpt-3.5-turbo" => "gpt-3.5-turbo",

    # Anthropic normalizations
    "claude-3-5-haiku" => "claude-3-5-haiku-20241022",
    "claude-3-5-sonnet" => "claude-3-5-sonnet-20241022",
    "claude-3-opus" => "claude-3-opus-20240229",

    # Google normalizations (strip models/ prefix)
    "models/gemini-2.0-flash" => "gemini-2.0-flash",
    "models/gemini-1.5-pro" => "gemini-1.5-pro",
    "gemini-2.0-flash" => "gemini-2.0-flash",
    "gemini-1.5-pro" => "gemini-1.5-pro"
  }

  # Deprecated models and their recommended replacements.
  @deprecated_models %{
    "gpt-3.5-turbo-0301" => "gpt-3.5-turbo",
    "gpt-4-0314" => "gpt-4",
    "claude-2" => "claude-3-5-haiku",
    "claude-1" => "claude-3-5-haiku"
  }

  @doc """
  Gets the ReqLLM provider name for a given Jido AI provider.

  ## Parameters
    - jido_provider: Atom representing the Jido AI provider

  ## Returns
    - Atom representing the ReqLLM provider name

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.get_reqllm_provider(:openai)
      :openai

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.get_reqllm_provider(:anthropic)
      :anthropic
  """
  @spec get_reqllm_provider(atom()) :: atom()
  def get_reqllm_provider(jido_provider) when is_atom(jido_provider) do
    Map.get(@provider_mapping, jido_provider, jido_provider)
  end

  @doc """
  Normalizes a model name for ReqLLM format requirements.

  This function applies known normalization rules and handles common
  model name variations to ensure compatibility with ReqLlmBridge.

  ## Parameters
    - model_name: String representing the model name

  ## Returns
    - Normalized model name string

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.normalize_model_name("models/gemini-2.0-flash")
      "gemini-2.0-flash"

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.normalize_model_name("gpt-4o")
      "gpt-4o"
  """
  @spec normalize_model_name(String.t()) :: String.t()
  def normalize_model_name(model_name) when is_binary(model_name) do
    # Apply known normalizations
    normalized = Map.get(@model_normalizations, model_name, model_name)

    # Additional normalization rules
    normalized
    |> String.trim()
    |> remove_version_suffixes_if_needed()
  end

  @doc """
  Checks if a model is deprecated and returns a replacement if available.

  ## Parameters
    - model_name: String representing the model name

  ## Returns
    - `{:ok, model_name}` if the model is current
    - `{:deprecated, replacement}` if the model is deprecated with a suggested replacement
    - `{:error, reason}` if the model is unsupported

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.check_model_deprecation("gpt-4o")
      {:ok, "gpt-4o"}

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.check_model_deprecation("claude-2")
      {:deprecated, "claude-3-5-haiku"}
  """
  @spec check_model_deprecation(String.t()) ::
          {:ok, String.t()} | {:deprecated, String.t()} | {:error, String.t()}
  def check_model_deprecation(model_name) when is_binary(model_name) do
    case Map.get(@deprecated_models, model_name) do
      nil -> {:ok, model_name}
      replacement -> {:deprecated, replacement}
    end
  end

  @doc """
  Validates that a ReqLLM model is available and supported.

  This function checks with ReqLLM to ensure the model exists and is accessible.
  Note: This is a placeholder for future ReqLLM integration - currently returns
  success for known providers.

  ## Parameters
    - reqllm_id: String in "provider:model" format
    - opts: Additional options (optional)

  ## Returns
    - `{:ok, model_info}` if the model is available
    - `{:error, reason}` if the model is not available

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.validate_model_availability("openai:gpt-4o")
      {:ok, %{provider: :openai, model: "gpt-4o", available: true}}
  """
  @spec validate_model_availability(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def validate_model_availability(reqllm_id, _opts \\ []) when is_binary(reqllm_id) do
    # First check for valid format
    if String.contains?(reqllm_id, ":") do
      case String.split(reqllm_id, ":", parts: 2) do
        [provider_str, model] when provider_str != "" and model != "" ->
          # Check if there are additional colons in the model part
          if String.contains?(model, ":") do
            {:error, "Invalid ReqLLM ID format. Expected 'provider:model', got: #{reqllm_id}"}
          else
            # Secure provider validation using ReqLLM's valid provider list
            # Create safe string-to-atom mapping to avoid arbitrary atom creation
            valid_providers =
              ValidProviders.list()
              |> Map.new(fn atom -> {to_string(atom), atom} end)

            case Map.get(valid_providers, provider_str) do
              nil ->
                {:error, "Unsupported provider: #{provider_str}"}

              provider_atom ->
                # In the future, this would make an actual ReqLLM API call
                # For now, we'll assume supported providers have available models
                {:ok,
                 %{
                   provider: provider_atom,
                   model: model,
                   available: true,
                   reqllm_id: reqllm_id,
                   validated_at: DateTime.utc_now()
                 }}
            end
          end

        _ ->
          {:error, "Invalid ReqLLM ID format. Expected 'provider:model', got: #{reqllm_id}"}
      end
    else
      {:error, "Invalid ReqLLM ID format. Expected 'provider:model', got: #{reqllm_id}"}
    end
  end

  @doc """
  Builds a complete ReqLLM model configuration from Jido AI provider and model information.

  This function orchestrates the full mapping process: provider mapping,
  model normalization, deprecation checking, and validation.

  ## Parameters
    - jido_provider: Atom representing the Jido AI provider
    - model_name: String representing the model name
    - opts: Additional options (optional)

  ## Returns
    - `{:ok, config}` with complete ReqLLM configuration
    - `{:error, reason}` if mapping fails
    - `{:deprecated, config}` if model is deprecated but replacement is available

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.build_reqllm_config(:openai, "gpt-4o")
      {:ok, %{
        jido_provider: :openai,
        reqllm_provider: :openai,
        original_model: "gpt-4o",
        normalized_model: "gpt-4o",
        reqllm_id: "openai:gpt-4o",
        available: true
      }}
  """
  @spec build_reqllm_config(atom(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()} | {:deprecated, map()}
  def build_reqllm_config(jido_provider, model_name, opts \\ []) do
    with {:ok, reqllm_provider} <- {:ok, get_reqllm_provider(jido_provider)},
         {:ok, normalized_model} <- {:ok, normalize_model_name(model_name)},
         deprecation_result <- check_model_deprecation(normalized_model),
         final_model <- get_final_model(deprecation_result),
         reqllm_id <- "#{reqllm_provider}:#{final_model}",
         {:ok, validation_info} <- validate_model_availability(reqllm_id, opts) do
      config = %{
        jido_provider: jido_provider,
        reqllm_provider: reqllm_provider,
        original_model: model_name,
        normalized_model: normalized_model,
        final_model: final_model,
        reqllm_id: reqllm_id,
        available: validation_info.available,
        validated_at: validation_info.validated_at,
        deprecation_status: get_deprecation_status(deprecation_result)
      }

      case deprecation_result do
        {:deprecated, _replacement} -> {:deprecated, config}
        _ -> {:ok, config}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns a list of supported providers from the ReqLLM registry.

  This function dynamically discovers all available providers from ReqLLM's
  comprehensive registry system.

  ## Returns
    - List of atoms representing supported providers
  """
  @spec supported_providers() :: [atom()]
  def supported_providers do
    ValidProviders.list()
  rescue
    _ ->
      # Fallback to mapped providers if registry unavailable
      Map.values(@provider_mapping) |> Enum.uniq()
  end

  @doc """
  Gets provider metadata in Jido format from ReqLLM provider information.

  This function bridges between ReqLLM's provider metadata structure and
  Jido AI's expected format, ensuring backward compatibility.

  ## Parameters
    - provider_id: Atom representing the provider

  ## Returns
    - `{:ok, metadata}` with provider information in Jido format
    - `{:error, reason}` if metadata cannot be retrieved

  ## Examples

      iex> Jido.AI.ReqLlmBridge.ProviderMapping.get_jido_provider_metadata(:openai)
      {:ok, %{
        id: :openai,
        name: "OpenAI",
        description: "OpenAI language models including GPT-4",
        type: :direct,
        requires_api_key: true,
        models: []
      }}
  """
  @spec get_jido_provider_metadata(atom()) :: {:ok, map()} | {:error, term()}
  def get_jido_provider_metadata(provider_id) when is_atom(provider_id) do
    # For now, build metadata from what we know about providers
    # Issue: Fetch actual metadata from ReqLLM when provider metadata API becomes available
    # Currently ReqLLM only provides list_providers(), list_models(), and get_model() methods
    metadata = %{
      id: provider_id,
      name: humanize_provider_name(provider_id),
      description: get_provider_description(provider_id),
      type: get_provider_type(provider_id),
      api_base_url: get_provider_base_url(provider_id),
      requires_api_key: provider_requires_api_key?(provider_id),
      # Models loaded dynamically
      models: []
    }

    {:ok, metadata}
  end

  @doc """
  Checks if a provider is fully implemented in ReqLLM.

  ## Parameters
    - provider_id: Atom representing the provider

  ## Returns
    - Boolean indicating if the provider has full ReqLLM implementation
  """
  @spec provider_implemented?(atom()) :: boolean()
  def provider_implemented?(provider_id) when is_atom(provider_id) do
    # Check if provider is in the ValidProviders list
    provider_id in supported_providers()
  end

  defp humanize_provider_name(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp get_provider_description(provider_id) do
    descriptions = %{
      openai: "OpenAI language models including GPT-4 and GPT-3.5",
      anthropic: "Anthropic's Claude family of AI assistants",
      google: "Google's Gemini and PaLM language models",
      openrouter: "Unified API gateway for multiple AI providers",
      cloudflare: "Cloudflare Workers AI platform",
      mistral: "Mistral AI's open and commercial models",
      cohere: "Cohere's language understanding and generation models",
      together: "Together AI's optimized model inference platform",
      perplexity: "Perplexity AI's information-focused models",
      groq: "Groq's high-performance LPU inference",
      deepinfra: "DeepInfra's scalable model hosting",
      replicate: "Replicate's model deployment platform"
    }

    Map.get(descriptions, provider_id, "Provider available through ReqLLM integration")
  end

  defp get_provider_type(provider_id) do
    # Proxy providers vs direct providers
    proxy_providers = [:openrouter, :together, :deepinfra, :replicate]

    if provider_id in proxy_providers do
      :proxy
    else
      :direct
    end
  end

  defp get_provider_base_url(provider_id) do
    base_urls = %{
      openai: "https://api.openai.com/v1",
      anthropic: "https://api.anthropic.com",
      google: "https://generativelanguage.googleapis.com",
      openrouter: "https://openrouter.ai/api/v1",
      cloudflare: "https://api.cloudflare.com",
      mistral: "https://api.mistral.ai",
      cohere: "https://api.cohere.ai",
      groq: "https://api.groq.com"
    }

    Map.get(base_urls, provider_id)
  end

  defp provider_requires_api_key?(provider_id) do
    # Most providers require API keys
    # Only a few local or open providers might not
    no_key_providers = [:ollama, :llamacpp, :local]

    provider_id not in no_key_providers
  end

  @doc """
  Logs provider mapping operations for debugging and monitoring.

  ## Parameters
    - level: Log level (:debug, :info, :warning, :error)
    - operation: String describing the operation
    - details: Map with additional details
  """
  @spec log_mapping_operation(atom(), String.t(), map()) :: :ok
  def log_mapping_operation(level, operation, details \\ %{}) do
    if Application.get_env(:jido_ai, :enable_provider_mapping_logging, false) do
      Logger.log(
        level,
        "[Provider Mapping] #{operation}",
        Keyword.merge([module: __MODULE__], Map.to_list(details))
      )
    end

    :ok
  end

  # Private helper functions

  defp remove_version_suffixes_if_needed(model_name) do
    # Remove common version suffixes that might not be needed
    # This is conservative - only removes known safe patterns
    model_name
    # Remove date suffixes like -20241022
    |> String.replace(~r/-\d{8}$/, "")
    # Remove version suffixes like -v1
    |> String.replace(~r/-v\d+$/, "")
  end

  defp get_final_model({:ok, model}), do: model
  defp get_final_model({:deprecated, replacement}), do: replacement

  defp get_deprecation_status({:ok, _}), do: :current
  defp get_deprecation_status({:deprecated, _}), do: :deprecated
end
