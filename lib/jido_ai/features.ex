defmodule Jido.AI.Features do
  @moduledoc """
  Feature detection and capability queries for specialized model features.

  This module provides detection for advanced features that extend beyond
  basic chat completion, including RAG, code execution, plugins, and fine-tuning.

  ## Supported Features

  - **RAG (Retrieval-Augmented Generation)**: Document-based context injection
  - **Code Execution**: Ability to execute code during generation
  - **Plugins**: Model-specific extensions and tools
  - **Fine-Tuning**: Custom trained model variants

  ## Usage

      # Check if a model supports RAG
      iex> Jido.AI.Features.supports?(model, :rag)
      true

      # Get all supported features for a model
      iex> Jido.AI.Features.capabilities(model)
      [:rag, :fine_tuning]

      # Check if a feature is available for a provider
      iex> Jido.AI.Features.provider_supports?(:cohere, :rag)
      true
  """

  alias Jido.AI.Model

  @type feature :: :rag | :code_execution | :plugins | :fine_tuning
  @type provider :: atom()

  # Provider feature support matrix based on research
  @provider_features %{
    cohere: [:rag, :fine_tuning],
    anthropic: [:rag, :plugins],
    openai: [:code_execution, :plugins, :fine_tuning],
    google: [:rag, :plugins, :fine_tuning],
    groq: [],
    together: [:fine_tuning],
    openrouter: [],
    ollama: [],
    llamacpp: []
  }

  @doc """
  Check if a model supports a specific feature.

  Determines feature support based on provider capabilities and model metadata.

  ## Parameters
    - model: Jido.AI.Model struct or model ID string
    - feature: Feature atom (:rag, :code_execution, :plugins, :fine_tuning)

  ## Returns
    Boolean indicating feature support

  ## Examples

      iex> Jido.AI.Features.supports?(model, :rag)
      true

      iex> Jido.AI.Features.supports?("cohere:command-r", :rag)
      true
  """
  @spec supports?(Model.t() | String.t(), feature()) :: boolean()
  def supports?(%Model{provider: provider} = model, feature) when is_atom(feature) do
    # Check provider-level support first
    if provider_supports?(provider, feature) do
      # Additional model-specific checks
      case feature do
        :fine_tuning -> fine_tuned_model?(model)
        :code_execution -> model_supports_code_execution?(model)
        _ -> true
      end
    else
      false
    end
  end

  def supports?(model_id, feature) when is_binary(model_id) do
    case Model.from(model_id) do
      {:ok, model} -> supports?(model, feature)
      {:error, _} -> false
    end
  end

  @doc """
  Get all supported features for a model.

  Returns a list of feature atoms supported by the model.

  ## Parameters
    - model: Jido.AI.Model struct or model ID string

  ## Returns
    List of supported feature atoms

  ## Examples

      iex> Jido.AI.Features.capabilities(model)
      [:rag, :fine_tuning]
  """
  @spec capabilities(Model.t() | String.t()) :: [feature()]
  def capabilities(%Model{provider: provider} = model) do
    base_features = Map.get(@provider_features, provider, [])

    # Add fine-tuning if this is a fine-tuned model
    features =
      if fine_tuned_model?(model) and :fine_tuning not in base_features do
        [:fine_tuning | base_features]
      else
        base_features
      end

    # Filter out code execution if not explicitly supported
    Enum.filter(features, fn feature ->
      case feature do
        :code_execution -> model_supports_code_execution?(model)
        _ -> true
      end
    end)
  end

  def capabilities(model_id) when is_binary(model_id) do
    case Model.from(model_id) do
      {:ok, model} -> capabilities(model)
      {:error, _} -> []
    end
  end

  @doc """
  Check if a provider supports a specific feature.

  ## Parameters
    - provider: Provider atom
    - feature: Feature atom

  ## Returns
    Boolean indicating provider-level support

  ## Examples

      iex> Jido.AI.Features.provider_supports?(:cohere, :rag)
      true

      iex> Jido.AI.Features.provider_supports?(:ollama, :rag)
      false
  """
  @spec provider_supports?(provider(), feature()) :: boolean()
  def provider_supports?(provider, feature) when is_atom(provider) and is_atom(feature) do
    features = Map.get(@provider_features, provider, [])
    feature in features
  end

  @doc """
  Get all features supported by a provider.

  ## Parameters
    - provider: Provider atom

  ## Returns
    List of feature atoms

  ## Examples

      iex> Jido.AI.Features.provider_features(:cohere)
      [:rag, :fine_tuning]
  """
  @spec provider_features(provider()) :: [feature()]
  def provider_features(provider) when is_atom(provider) do
    Map.get(@provider_features, provider, [])
  end

  @doc """
  Get all providers that support a specific feature.

  ## Parameters
    - feature: Feature atom

  ## Returns
    List of provider atoms

  ## Examples

      iex> Jido.AI.Features.providers_for(:rag)
      [:cohere, :anthropic, :google]
  """
  @spec providers_for(feature()) :: [provider()]
  def providers_for(feature) when is_atom(feature) do
    @provider_features
    |> Enum.filter(fn {_provider, features} -> feature in features end)
    |> Enum.map(fn {provider, _features} -> provider end)
  end

  # Private helper functions

  # Check if a model is a fine-tuned variant
  defp fine_tuned_model?(%Model{model: model_id}) do
    # OpenAI fine-tuned models: ft:gpt-4-0613:org:suffix:id
    # Google fine-tuned models: projects/*/locations/*/models/*
    String.starts_with?(model_id, "ft:") or String.contains?(model_id, "/models/")
  end

  # Check if a model specifically supports code execution
  # Currently only OpenAI models via Assistants API with code_interpreter tool
  defp model_supports_code_execution?(%Model{provider: :openai, model: model_id}) do
    # GPT-4 and GPT-3.5 models support code interpreter
    String.contains?(model_id, "gpt-4") or String.contains?(model_id, "gpt-3.5")
  end

  defp model_supports_code_execution?(_model), do: false
end
