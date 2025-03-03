defmodule Jido.AI.Provider.Cloudflare do
  @moduledoc """
  Adapter for the Cloudflare AI provider.

  Implements the ProviderBehavior for Cloudflare's AI API.
  """
  @behaviour Jido.AI.Model.Provider.Adapter
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Helpers

  @base_url "https://api.cloudflare.com/client/v4/accounts"
  @provider_id :cloudflare
  @provider_path "cloudflare"

  @impl true
  def definition do
    %Provider{
      id: @provider_id,
      name: "Cloudflare",
      description: "Cloudflare's AI Gateway provides access to multiple AI models",
      type: :proxy,
      api_base_url: @base_url,
      requires_api_key: true
    }
  end

  @impl true
  @doc """
  Lists available models from local cache or API.

  ## Options
    - refresh: boolean - Whether to force refresh from API (default: false)
    - api_key: string - Cloudflare API key (optional)
    - email: string - Cloudflare account email (optional)
    - account_id: string - Cloudflare account ID (required)

  Returns a tuple with {:ok, models} on success or {:error, reason} on failure.
  """
  def list_models(opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)
    models_file = Helpers.get_models_file_path(@provider_path)

    cond do
      refresh ->
        fetch_and_cache_models(opts)

      File.exists?(models_file) ->
        read_models_from_cache()

      true ->
        fetch_and_cache_models(opts)
    end
  end

  @impl true
  @doc """
  Fetches a specific model by ID from the API or cache.

  ## Options
    - refresh: boolean - Whether to force refresh from API (default: false)
    - api_key: string - Cloudflare API key (optional)
    - email: string - Cloudflare account email (optional)
    - account_id: string - Cloudflare account ID (required)

  Returns a tuple with {:ok, model} on success or {:error, reason} on failure.
  """
  def model(model_id, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    if refresh do
      fetch_model_from_api(model_id, opts)
    else
      case fetch_model_from_cache(model_id, opts) do
        {:ok, model} -> {:ok, model}
        {:error, _} -> fetch_model_from_api(model_id, opts)
      end
    end
  end

  @impl true
  def normalize(model_id, _opts \\ []) do
    {:ok, model_id}
  end

  @impl true
  def base_url() do
    @base_url
  end

  @impl true
  def request_headers(opts) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("CLOUDFLARE_API_KEY")
    email = Keyword.get(opts, :email) || System.get_env("CLOUDFLARE_EMAIL")

    base_headers = %{
      "Content-Type" => "application/json"
    }

    headers =
      if api_key do
        Map.put(base_headers, "X-Auth-Key", api_key)
      else
        base_headers
      end

    if email do
      Map.put(headers, "X-Auth-Email", email)
    else
      headers
    end
  end

  @impl true
  def validate_model_opts(opts) do
    {:ok, %Jido.AI.Model{
      id: opts[:model_id] || "cloudflare_default",
      name: opts[:model_name] || "Cloudflare Model",
      provider: :cloudflare
    }}
  end

  @impl true
  @doc """
  Builds a %Jido.AI.Model{} struct from the provided options.

  This function validates the options, sets defaults, and creates a fully populated
  model struct for the Cloudflare provider.

  ## Parameters
    - opts: Keyword list of options for building the model

  ## Returns
    - {:ok, %Jido.AI.Model{}} on success
    - {:error, reason} on failure
  """
  def build(opts) do
    # Extract or generate an API key
    api_key = Helpers.get_api_key(opts, "CLOUDFLARE_API_KEY", :cloudflare_api_key)

    # Get model_id from opts
    model_id = Keyword.get(opts, :model_id)

    # Validate model_id
    if is_nil(model_id) do
      {:error, "model_id is required for Cloudflare models"}
    else
      # Create the model struct with all necessary fields
      model = %Jido.AI.Model{
        id: Keyword.get(opts, :id, "cloudflare_#{model_id}"),
        name: Keyword.get(opts, :name, "Cloudflare #{model_id}"),
        provider: :cloudflare,
        model_id: model_id,
        base_url: @base_url,
        api_key: api_key,
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens, 1024),
        max_retries: Keyword.get(opts, :max_retries, 0),
        architecture: %Jido.AI.Model.Architecture{
          modality: Keyword.get(opts, :modality, "text"),
          tokenizer: Keyword.get(opts, :tokenizer, "unknown"),
          instruct_type: Keyword.get(opts, :instruct_type)
        },
        description: Keyword.get(opts, :description, "Cloudflare model"),
        created: System.system_time(:second),
        endpoints: []
      }

      {:ok, model}
    end
  end

  @impl true
  def transform_model_to_clientmodel(_client_atom, _model) do
    {:error, "Not implemented yet"}
  end

  # Private helper functions

  defp read_models_from_cache do
    case File.read(Helpers.get_models_file_path(@provider_path)) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"result" => models}} ->
            {:ok, process_models(models)}

          {:error, reason} ->
            {:error, "Failed to parse cached models: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read models cache: #{inspect(reason)}"}
    end
  end

  defp fetch_model_from_cache(model_id, opts) do
    model_file = Helpers.get_model_file_path(@provider_path, model_id)

    if File.exists?(model_file) do
      case File.read(model_file) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, model_data} ->
              {:ok, process_single_model(model_data, model_id)}

            {:error, reason} ->
              {:error, "Failed to parse cached model: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to read model cache: #{inspect(reason)}"}
      end
    else
      case list_models(Keyword.put(opts, :refresh, false)) do
        {:ok, models} ->
          case Enum.find(models, fn model -> model.id == model_id end) do
            nil -> {:error, "Model not found in cache: #{model_id}"}
            model -> {:ok, model}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_and_cache_models(opts) do
    account_id = Keyword.get(opts, :account_id) || System.get_env("CLOUDFLARE_ACCOUNT_ID")
    url = "#{base_url()}/accounts/#{account_id}/ai/models/search"
    headers = request_headers(opts)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"result" => models}}} ->
        models_file = Helpers.get_models_file_path(@provider_path)
        File.mkdir_p!(Path.dirname(models_file))

        json = Jason.encode!(%{"result" => models}, pretty: true)
        File.write!(models_file, json)

        {:ok, process_models(models)}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch models: #{inspect(reason)}"}
    end
  end

  defp fetch_model_from_api(model_id, opts) do
    account_id = Keyword.get(opts, :account_id) || System.get_env("CLOUDFLARE_ACCOUNT_ID")
    url = "#{base_url()}/accounts/#{account_id}/ai/models/schema"
    headers = request_headers(opts)
    body = Jason.encode!(%{model_id: model_id})

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: %{"result" => model_data}}} ->
        processed_model = process_single_model(model_data, model_id)

        if Keyword.get(opts, :save_to_cache, true) do
          cache_single_model(model_id, model_data)
        end

        {:ok, processed_model}

      {:ok, %{status: status, body: body}} ->
        {:error, "API request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch model: #{inspect(reason)}"}
    end
  end

  defp cache_single_model(model_id, model_data) do
    # Ensure the models directory exists
    base_dir = Jido.AI.Provider.base_dir()
    provider_dir = Path.join(base_dir, @provider_path)
    model_dir = Path.join(provider_dir, "models")

    # Create the models directory if it doesn't exist
    unless File.exists?(model_dir) do
      File.mkdir_p!(model_dir)
    end

    model_file = Helpers.get_model_file_path(@provider_path, model_id)
    json = Jason.encode!(model_data, pretty: true)
    File.write!(model_file, json)
  end

  defp process_models(models) when is_list(models) do
    Enum.map(models, fn model ->
      %{
        id: model["id"],
        name: model["name"],
        description: model["description"] || "",
        created: model["created"],
        capabilities: extract_capabilities(model),
        tier: determine_tier(model)
      }
    end)
  end

  defp process_models(_), do: []

  defp process_single_model(model_data, model_id) when is_map(model_data) do
    %{
      id: model_id,
      name: model_data["name"] || model_id,
      description: model_data["description"] || "",
      created: model_data["created"],
      capabilities: extract_capabilities(model_data),
      tier: determine_tier(model_data)
    }
  end

  defp extract_capabilities(model) do
    task_type = model["task_type"] || ""

    %{
      chat: String.contains?(task_type, "text-generation"),
      embedding: String.contains?(task_type, "embedding"),
      image: String.contains?(task_type, "image"),
      vision: String.contains?(task_type, "vision"),
      multimodal: String.contains?(task_type, "multimodal"),
      audio: String.contains?(task_type, "audio"),
      code: String.contains?(task_type, "code")
    }
  end

  defp determine_tier(model) do
    case model["tier"] || "basic" do
      "advanced" -> %{value: :advanced, description: "High-performance model"}
      "standard" -> %{value: :standard, description: "Balanced performance and cost"}
      _ -> %{value: :basic, description: "Entry-level model"}
    end
  end
end
