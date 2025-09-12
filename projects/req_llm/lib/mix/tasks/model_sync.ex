defmodule Mix.Tasks.ReqLlm.ModelSync do
  @moduledoc """
  Simplified model synchronization task.

  This task fetches model data from models.dev API (which now includes cost data)
  and saves provider JSON files to the /priv directory.

  ## Usage

      # Sync models from models.dev
      mix req_llm.model_sync

      # Verbose output
      mix req_llm.model_sync --verbose

  ## Output Structure

      priv/models_dev/providers/
      ├── anthropic.json         # Anthropic models with cost data
      ├── openai.json            # OpenAI models with cost data
      ├── google.json            # Google models with cost data
      └── ...                    # All other providers
  """

  use Mix.Task

  @shortdoc "Synchronize model data from models.dev API"

  require Logger

  # API endpoint
  @models_dev_api "https://models.dev/api.json"

  # Directory structure
  @providers_dir "priv/models_dev"

  # Fields we don't need from models.dev that should be filtered out
  @unused_fields ~w[
    npm
    packageName
    license
    repository
    bugs
    homepage
    engines
    keywords
    exports
    dependencies
  ]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:req_llm)

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          verbose: :boolean
        ]
      )

    verbose? = Keyword.get(opts, :verbose, false)

    if verbose?, do: IO.puts("Starting model synchronization...")

    case execute_sync(verbose?) do
      :ok ->
        IO.puts("Model synchronization completed successfully")

      {:error, reason} ->
        IO.puts("Synchronization failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Execute the synchronization process.
  """
  @spec execute_sync(boolean()) :: :ok | {:error, term()}
  def execute_sync(verbose? \\ false) do
    File.mkdir_p!(@providers_dir)

    with {:ok, models_data} <- fetch_models_dev_data(verbose?) do
      save_provider_files(models_data, verbose?)
    end
  end

  defp fetch_models_dev_data(verbose?) do
    if verbose?, do: IO.puts("Fetching models.dev catalog...")

    case Req.get(@models_dev_api) do
      {:ok, %{status: 200, body: data}} ->
        if verbose? do
          provider_count = map_size(data)
          model_count = count_total_models(data)

          IO.puts(
            "Downloaded models.dev data: #{provider_count} providers, #{model_count} models"
          )
        end

        {:ok, data}

      {:ok, %{status: status}} ->
        {:error,
         ReqLLM.Error.API.Response.exception(
           reason: "models.dev API returned status #{status}",
           status: status
         )}

      {:error, reason} ->
        {:error,
         ReqLLM.Error.API.Request.exception(
           reason: "Failed to fetch models.dev data: #{inspect(reason)}"
         )}
    end
  end

  defp save_provider_files(models_data, verbose?) do
    models_data
    |> Enum.each(fn {provider_id, provider_data} ->
      models = process_provider_models(provider_data["models"] || %{}, provider_id)

      if not Enum.empty?(models) do
        provider_file = Path.join(@providers_dir, "#{provider_id}.json")
        config = get_provider_config(provider_id)

        provider_json = %{
          "provider" => %{
            "id" => provider_id,
            "name" => provider_data["name"] || format_provider_name(provider_id),
            "base_url" => config["base_url"],
            "env" => config["env"] || [],
            "doc" => provider_data["description"] || "AI model provider"
          },
          "models" => prune_model_fields(models)
        }

        File.write!(provider_file, Jason.encode!(provider_json, pretty: true))

        if verbose? do
          IO.puts("  Saved #{length(models)} models for #{provider_id}")
        end
      end
    end)

    :ok
  end

  defp process_provider_models(models_map, provider_id) do
    models_map
    |> Enum.map(fn {_model_id, model_data} ->
      Map.merge(model_data, %{
        "provider" => provider_id,
        "provider_model_id" => model_data["id"]
      })
    end)
  end

  defp prune_model_fields(models) do
    models
    |> Enum.map(fn model ->
      Enum.reduce(@unused_fields, model, fn field, acc ->
        Map.delete(acc, field)
      end)
    end)
  end

  defp count_total_models(providers_data) do
    providers_data
    |> Enum.map(fn {_, provider} -> map_size(provider["models"] || %{}) end)
    |> Enum.sum()
  end

  defp format_provider_name(provider_id) do
    provider_id
    |> String.split(["-", "_"])
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # Provider-specific configuration (missing from models.dev)
  # Simplified - no module attribute, inline function
  defp get_provider_config("openai") do
    %{
      "base_url" => "https://api.openai.com/v1",
      "env" => ["OPENAI_API_KEY"]
    }
  end

  defp get_provider_config("anthropic") do
    %{
      "base_url" => "https://api.anthropic.com/v1",
      "env" => ["ANTHROPIC_API_KEY"]
    }
  end

  defp get_provider_config("openrouter") do
    %{
      "base_url" => "https://openrouter.ai/api/v1",
      "env" => ["OPENROUTER_API_KEY"]
    }
  end

  defp get_provider_config("google") do
    %{
      "base_url" => "https://generativelanguage.googleapis.com/v1",
      "env" => ["GOOGLE_API_KEY"]
    }
  end

  defp get_provider_config("cloudflare") do
    %{
      "base_url" => "https://api.cloudflare.com/client/v4/accounts",
      "env" => ["CLOUDFLARE_API_KEY"]
    }
  end

  defp get_provider_config(_provider_id) do
    %{}
  end
end
