defmodule ReqLLM.Capability do
  @moduledoc """
  Model capability discovery and validation.
  
  This module dynamically extracts capabilities from provider metadata
  loaded from models.dev, providing a programmatic interface to query
  what features are supported by specific models.
  """

  alias ReqLLM.Provider.Registry

  # Core capability mappings from models.dev JSON fields to our feature atoms
  # Using functions instead of module attributes to avoid compilation issues
  defp capability_supported?(capability, metadata) do
    case capability do
      # Basic generation features - all models support these
      :max_tokens -> true
      :system_prompt -> true
      :metadata -> true
      
      # Sampling parameters
      :temperature -> Map.get(metadata, "temperature", false)
      :top_p -> Map.get(metadata, "top_p", false) 
      :top_k -> Map.get(metadata, "top_k", false)
      
      # Advanced features
      :tools -> Map.get(metadata, "tool_call", false)
      :tool_choice -> Map.get(metadata, "tool_call", false)
      :reasoning -> Map.get(metadata, "reasoning", false)
      
      # Response control
      :stop_sequences -> true  # Most models support this
      :streaming -> Map.get(metadata, "streaming", true)
      
      # Unknown capabilities default to false
      _ -> false
    end
  end

  @doc """
  Get all supported capabilities for a model spec.
  
  ## Examples
  
      iex> ReqLLM.Capability.for("anthropic:claude-3-haiku-20240307")
      [:max_tokens, :system_prompt, :temperature, :tools, :streaming, :metadata]
      
  """
  def for(model_spec) when is_binary(model_spec) do
    case parse_model_spec(model_spec) do
      {:ok, provider, model_name} ->
        case get_model_metadata(provider, model_name) do
          {:ok, metadata} ->
            # Get all possible capabilities and filter by what's supported
            all_capabilities = [
              :max_tokens, :system_prompt, :temperature, :top_p, :top_k,
              :tools, :tool_choice, :reasoning, :stop_sequences, :streaming, :metadata
            ]
            
            all_capabilities
            |> Enum.filter(&capability_supported?(&1, metadata))
            
          {:error, :model_not_found} ->
            # Model doesn't exist for this provider
            []
            
          {:error, _reason} ->
            # Provider exists but metadata unavailable - fallback to basic capabilities
            [:max_tokens, :system_prompt, :metadata]
        end
        
      :error ->
        []
    end
  end

  def for(%ReqLLM.Model{provider: provider, model: model_name}) do
    model_spec = "#{provider}:#{model_name}"
    __MODULE__.for(model_spec)
  end

  @doc """
  Check if a model supports a specific feature.
  
  ## Examples
  
      iex> ReqLLM.Capability.supports?("anthropic:claude-3-sonnet-20240229", :tools)
      true
      
  """
  def supports?(model_spec, feature) when is_atom(feature) do
    feature in __MODULE__.for(model_spec)
  end

  @doc """
  Get all models that support a specific feature for a provider.
  
  ## Examples
  
      iex> ReqLLM.Capability.models_for(:anthropic, :reasoning)
      ["anthropic:claude-3-5-sonnet-20241022"]
      
  """
  def models_for(provider, feature) when is_atom(provider) and is_atom(feature) do
    case Registry.list_models(provider) do
      {:ok, model_names} ->
        model_names
        |> Enum.map(&"#{provider}:#{&1}")
        |> Enum.filter(&supports?(&1, feature))
        
      {:error, _reason} ->
        []
    end
  end

  @doc """
  Get all available models for a provider as model specs.
  
  ## Examples
  
      iex> ReqLLM.Capability.provider_models(:anthropic)
      ["anthropic:claude-3-haiku-20240307", "anthropic:claude-3-sonnet-20240229", ...]
      
  """
  def provider_models(provider) when is_atom(provider) do
    case Registry.list_models(provider) do
      {:ok, model_names} ->
        Enum.map(model_names, &"#{provider}:#{&1}")
        
      {:error, _reason} ->
        []
    end
  end

  @doc """
  Get all providers that have models supporting a feature.
  """
  def providers_for(feature) when is_atom(feature) do
    Registry.list_providers()
    |> Enum.filter(fn provider ->
      !Enum.empty?(models_for(provider, feature))
    end)
  end

  # Helper functions

  defp parse_model_spec(model_spec) when is_binary(model_spec) do
    case String.split(model_spec, ":", parts: 2) do
      [provider_str, model_name] ->
        try do
          provider = String.to_existing_atom(provider_str)
          {:ok, provider, model_name}
        rescue
          ArgumentError -> :error  # Provider atom doesn't exist
        end
      _ ->
        :error
    end
  end

  defp get_model_metadata(provider, model_name) do
    case Registry.get_provider_metadata(provider) do
      {:ok, provider_metadata} ->
        # metadata may come with atom keys (new DSL) or string keys (older files)
        models =
          Map.get(provider_metadata, :models) ||
          Map.get(provider_metadata, "models") ||
          []

        case Enum.find(models, fn model ->
               (Map.get(model, :id) || Map.get(model, "id")) == model_name
             end) do
          nil -> {:error, :model_not_found}
          model_metadata -> {:ok, model_metadata}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
