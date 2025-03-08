defmodule Jido.AI.Provider.Helpers do
  @moduledoc """
  Common helper functions for AI provider adapters.

  This module centralizes functionality that would otherwise be duplicated
  across provider implementations, such as:
  - File path management for model caching
  - Reading from and writing to cache
  - Making API requests with proper authentication
  - Model name standardization across providers
  """

  require Logger
  alias Jido.AI.Keyring

  @model_patterns [
    {~r/claude-3\.7-sonnet/i, "claude-3.7-sonnet"},
    {~r/claude-3\.5-sonnet/i, "claude-3.5-sonnet"},
    {~r/claude-3-opus/i, "claude-3-opus"},
    {~r/gpt-4o-mini/i, "gpt-4o-mini"},
    {~r/gpt-4o/i, "gpt-4o"},
    {~r/gpt-4/i, "gpt-4"},
    {~r/gpt-3\.5/i, "gpt-3.5"},
    {~r/mistral-7b/i, "mistral-7b"},
    {~r/mistral-8x7b/i, "mistral-8x7b"},
    {~r/llama-2-70b/i, "llama-2-70b"},
    {~r/llama-2-13b/i, "llama-2-13b"},
    {~r/llama-2-7b/i, "llama-2-7b"}
  ]

  @doc """
  Standardizes a model name across providers by removing version numbers and dates.
  This helps match equivalent models from different providers.

  ## Examples
      iex> standardize_name("claude-3.7-sonnet-20250219")
      "claude-3.7-sonnet"
      iex> standardize_name("gpt-4-0613")
      "gpt-4"
  """
  def standardize_name(model_id) when is_binary(model_id) do
    # First try exact matches from our patterns
    case Enum.find_value(@model_patterns, fn {pattern, standard_name} ->
           if String.match?(model_id, pattern), do: standard_name, else: nil
         end) do
      nil ->
        # If no exact match, try to remove version/date suffixes
        model_id
        |> remove_version_suffix()
        |> remove_date_suffix()

      standard_name ->
        standard_name
    end
  end

  def standardize_name(model_id), do: model_id

  # Remove version suffixes like -0613, -1106, etc.
  defp remove_version_suffix(model_id) do
    Regex.replace(~r/-[0-9]{4}$/, model_id, "")
  end

  # Remove date suffixes like -20250219, -20241022, etc.
  defp remove_date_suffix(model_id) do
    Regex.replace(~r/-[0-9]{8}$/, model_id, "")
  end

  @doc """
  Gets the path to the models file for a provider.
  """
  def get_models_file_path(provider_path) do
    base_dir = Jido.AI.Provider.base_dir()
    provider_dir = Path.join(base_dir, provider_path)
    Path.join(provider_dir, "models.json")
  end

  @doc """
  Gets the path to a specific model file for a provider.
  """
  def get_model_file_path(provider_path, model_id) do
    base_dir = Jido.AI.Provider.base_dir()
    provider_dir = Path.join(base_dir, provider_path)
    model_dir = Path.join(provider_dir, "models")
    Path.join(model_dir, "#{model_id}.json")
  end

  @doc """
  Reads models from the cache file.
  """
  def read_models_from_cache(provider_path, process_fn) do
    file_path = get_models_file_path(provider_path)

    with {:ok, json} <- File.read(file_path),
         {:ok, data} <- parse_json(json) do
      case data do
        %{"data" => models} when is_list(models) ->
          {:ok, process_fn.(models)}

        models when is_list(models) ->
          {:ok, process_fn.(models)}

        data ->
          # Try to extract models from different response formats
          models = extract_models_from_response(data)
          {:ok, process_fn.(models)}
      end
    else
      {:error, reason} -> {:error, "Failed to read or parse models cache: #{inspect(reason)}"}
    end
  end

  # Helper function to parse JSON with proper error handling
  defp parse_json(json) do
    try do
      Jason.decode(json)
    rescue
      e -> {:error, "Invalid JSON: #{inspect(e)}"}
    end
  end

  @doc """
  Fetches a model from the cache.
  """
  def fetch_model_from_cache(provider_path, model_id, _opts, process_fn) do
    # First try to read from the dedicated model file
    model_file = get_model_file_path(provider_path, model_id)

    if File.exists?(model_file) do
      case File.read(model_file) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, model_data} ->
              {:ok, process_fn.(model_data, model_id)}

            {:error, reason} ->
              {:error, "Failed to parse cached model: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to read model cache: #{inspect(reason)}"}
      end
    else
      # If no dedicated file exists, try to find in the models list
      case read_models_from_cache(provider_path, fn models ->
             # Process each model individually
             Enum.map(models, fn model ->
               process_fn.(model, model["id"])
             end)
           end) do
        {:ok, processed_models} ->
          # Find the specific model by ID
          case Enum.find(processed_models, fn model -> model.id == model_id end) do
            nil -> {:error, "Model not found in cache: #{model_id}"}
            model -> {:ok, model}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fetches models from the API and caches them.
  """
  def fetch_and_cache_models(_provider, url, headers, provider_path, process_fn) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        # Extract models from the response
        models = extract_models_from_response(body)

        # Ensure cache directory exists
        models_file = get_models_file_path(provider_path)
        File.mkdir_p!(Path.dirname(models_file))

        # Cache the response
        json = Jason.encode!(%{"data" => models}, pretty: true)
        File.write!(models_file, json)

        # Return processed models
        {:ok, process_fn.(models)}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch models: #{inspect(reason)}"}
    end
  end

  @doc """
  Fetches a specific model from the API and caches it.
  """
  def fetch_model_from_api(
        _provider,
        url,
        headers,
        model_id,
        provider_path,
        process_fn,
        opts \\ []
      ) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        # Process the model data
        model_data = extract_model_from_response(body)
        processed_model = process_fn.(model_data, model_id)

        # Cache the model data if requested
        if Keyword.get(opts, :save_to_cache, true) do
          cache_single_model(provider_path, model_id, model_data)
        end

        {:ok, processed_model}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch model: #{inspect(reason)}"}
    end
  end

  @doc """
  Caches a single model to a file.
  """
  def cache_single_model(provider_path, model_id, model_data) do
    model_file = get_model_file_path(provider_path, model_id)

    # Ensure model directory exists
    File.mkdir_p!(Path.dirname(model_file))

    # Save model to file
    json = Jason.encode!(model_data, pretty: true)
    File.write!(model_file, json)
  end

  @doc """
  Extracts models from different response formats.
  """
  def extract_models_from_response(%{"data" => models}) when is_list(models), do: models
  def extract_models_from_response(%{"models" => models}) when is_list(models), do: models
  def extract_models_from_response(models) when is_list(models), do: models
  def extract_models_from_response(data), do: [data]

  @doc """
  Extracts a model from different response formats.
  """
  def extract_model_from_response(%{"data" => model}), do: model
  def extract_model_from_response(%{"model" => model}), do: model
  def extract_model_from_response(model), do: model

  @doc """
  Gets an API key from options or environment.
  """
  def get_api_key(opts, env_var, keyring_key) do
    Keyword.get(opts, :api_key) ||
      Keyring.get(keyring_key) ||
      System.get_env(env_var)
  end

  @doc """
  Merges model information from multiple providers.

  ## Parameters
    - models: List of model maps from different providers

  ## Returns
    - A merged model map with combined information
  """
  def merge_model_information(models) do
    # Start with the first model as the base
    [base_model | other_models] = models

    # Get base capabilities, defaulting to empty map if not present
    base_capabilities =
      Map.get(base_model, :capabilities) || Map.get(base_model, "capabilities") || %{}

    # Merge capabilities from all models
    merged_capabilities =
      other_models
      |> Enum.reduce(base_capabilities, fn model, acc ->
        model_capabilities =
          Map.get(model, :capabilities) || Map.get(model, "capabilities") || %{}

        Map.merge(acc, model_capabilities, fn _k, v1, v2 -> v1 || v2 end)
      end)

    # Collect pricing information from all providers
    pricing_by_provider =
      models
      |> Enum.reduce(%{}, fn model, acc ->
        pricing = Map.get(model, :pricing) || Map.get(model, "pricing")

        if pricing && !is_nil(pricing) do
          Map.put(acc, model.provider, pricing)
        else
          acc
        end
      end)

    # Merge the rest of the information, prioritizing non-nil values
    other_models
    |> Enum.reduce(base_model, fn model, acc ->
      acc
      |> Map.merge(model, fn
        # Special handling for specific fields
        :capabilities, _, _ -> merged_capabilities
        "capabilities", _, _ -> merged_capabilities
        # Keep original provider
        :provider, v1, _v2 -> v1
        # Clear individual pricing (use pricing_by_provider instead)
        :pricing, _v1, _v2 -> nil
        # Clear individual pricing (use pricing_by_provider instead)
        "pricing", _v1, _v2 -> nil
        # Prefer v2 if not nil
        _k, v1, v2 -> v2 || v1
      end)
    end)
    |> Map.put(:pricing_by_provider, pricing_by_provider)
    |> Map.put(:available_from, Enum.map(models, & &1.provider))
  end
end
