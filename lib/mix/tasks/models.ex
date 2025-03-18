defmodule Mix.Tasks.Jido.Ai.Models do
  @moduledoc """
  Fetches and caches models from AI providers.

  This task provides a comprehensive interface for managing AI model information across different providers.
  It allows you to list, fetch, and view detailed information about models from various AI providers.

  ## Features

    * List available providers
    * List all cached models across providers
    * List models from specific providers
    * Fetch and cache models from providers
    * View detailed model information
    * Compare models across providers
    * Standardize model names across providers

  ## Examples

    # List all available providers
    mix jido.ai.models --list-providers

    # List all cached models (across all providers)
    mix jido.ai.models --list-all-models

    # List all cached models with verbose output
    mix jido.ai.models --list-all-models --verbose

    # List models from a specific provider
    mix jido.ai.models anthropic --list

    # List models from a specific provider with verbose output
    mix jido.ai.models anthropic --list --verbose

    # Fetch and cache all models from a provider
    mix jido.ai.models anthropic --fetch

    # Fetch and cache a specific model
    mix jido.ai.models anthropic --fetch --model=claude-3-7-sonnet-20250219

    # Fetch and cache all models from all providers
    mix jido.ai.models all --fetch

    # Show detailed information for a model (combined across providers)
    mix jido.ai.models --show=claude-3-7-sonnet

    # Show detailed information with raw data
    mix jido.ai.models --show=claude-3-7-sonnet --verbose

    # Refresh cached model information
    mix jido.ai.models anthropic --fetch --refresh

  ## Model Information Display

  When showing model information, the task displays:
    * Model name and description
    * Available providers
    * Capabilities (chat, embedding, image, vision, etc.)
    * Pricing information by provider
    * Model tier and description
    * Raw model data (with --verbose)

  ## Standardized Model Names

  The task automatically standardizes model names across providers:
    * claude-3-7-sonnet
    * claude-3-5-sonnet
    * claude-3-opus
    * gpt-4
    * gpt-3.5
    * mistral-7b
    * mistral-8x7b
    * llama-2-70b
    * llama-2-13b
    * llama-2-7b

  ## Cache Location

  Models are cached in the following location:
    _build/dev/lib/jido_ai/priv/provider/<provider_id>/models.json

  ## Options

    * --verbose: Show detailed information
    * --refresh: Force refresh of cached data
    * --model: Specify a model ID
    * --list: List models
    * --fetch: Fetch and cache models
    * --show: Show detailed model information
    * --list-providers: List available providers
    * --list-all-models: List all cached models
  """
  use Mix.Task
  require Logger
  alias Jido.AI.Provider

  @shortdoc "Fetches and caches models from an AI provider"

  @impl Mix.Task
  def run(args) do
    # Start the required applications
    Application.ensure_all_started(:jido_ai)

    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          verbose: :boolean,
          all: :boolean,
          refresh: :boolean,
          model: :string,
          list_providers: :boolean,
          list_all_models: :boolean,
          list: :boolean,
          fetch: :boolean,
          show: :string
        ]
      )

    verbose = Keyword.get(opts, :verbose, false)
    refresh = Keyword.get(opts, :refresh, false)
    specific_model = Keyword.get(opts, :model)

    cond do
      Keyword.get(opts, :list_providers, false) ->
        list_available_providers()

      Keyword.get(opts, :list_all_models, false) ->
        list_all_cached_models(opts)

      show_model = Keyword.get(opts, :show) ->
        show_combined_model_info(show_model, opts)

      Keyword.get(opts, :all, false) ->
        fetch_all_providers(verbose: verbose, refresh: refresh)

      specific_model && length(args) > 0 ->
        provider_id = List.first(args)
        fetch_specific_model(provider_id, specific_model, verbose: verbose, refresh: refresh)

      length(args) > 0 ->
        provider_id = List.first(args)
        handle_provider_operation(provider_id, opts)

      true ->
        show_usage()
    end
  end

  defp handle_provider_operation("all", opts) do
    if Keyword.get(opts, :fetch, false) do
      fetch_all_providers(opts)
    else
      list_models_from_all_providers(opts)
    end
  end

  defp handle_provider_operation(provider_id, opts) do
    cond do
      Keyword.get(opts, :list, false) ->
        list_provider_models(provider_id, opts)

      Keyword.get(opts, :fetch, false) && Keyword.get(opts, :model) ->
        model = Keyword.get(opts, :model)
        fetch_specific_model(provider_id, model, opts)

      Keyword.get(opts, :fetch, false) ->
        fetch_provider_models(provider_id, opts)

      true ->
        # Default behavior when no action specified
        list_provider_models(provider_id, opts)
    end
  end

  defp list_all_cached_models(opts) do
    verbose = Keyword.get(opts, :verbose, false)

    IO.puts("\nAll cached models (across all providers):")

    models = Provider.list_all_cached_models()

    if verbose do
      Enum.each(models, fn model ->
        print_model_details(model)
      end)
    else
      # Group models by standardized name
      models
      |> Enum.group_by(fn model ->
        model = Map.get(model, :id) || Map.get(model, "id")
        Jido.AI.Provider.standardize_model_name(model)
      end)
      |> Enum.each(fn {standard_name, models} ->
        providers = Enum.map(models, & &1.provider)
        IO.puts("\n#{standard_name} (available from: #{Enum.join(providers, ", ")})")
      end)
    end
  end

  defp show_combined_model_info(model_name, opts) do
    verbose = Keyword.get(opts, :verbose, false)

    case Provider.get_combined_model_info(model_name) do
      {:ok, model_info} ->
        print_combined_model_info(model_info, verbose)

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp print_combined_model_info(model_info, verbose) do
    name = Map.get(model_info, :name) || Map.get(model_info, "id") || "Unknown Model"
    description = Map.get(model_info, :description) || Map.get(model_info, "description") || "N/A"

    IO.puts("\nModel Information for: #{name}")
    IO.puts("Available from: #{Enum.join(model_info.available_from, ", ")}")
    IO.puts("Description: #{description}")

    capabilities = Map.get(model_info, :capabilities) || Map.get(model_info, "capabilities")

    if capabilities do
      IO.puts("\nCapabilities:")
      IO.puts("  Chat: #{Map.get(capabilities, :chat) || Map.get(capabilities, "chat")}")

      IO.puts(
        "  Embedding: #{Map.get(capabilities, :embedding) || Map.get(capabilities, "embedding")}"
      )

      IO.puts("  Image: #{Map.get(capabilities, :image) || Map.get(capabilities, "image")}")
      IO.puts("  Vision: #{Map.get(capabilities, :vision) || Map.get(capabilities, "vision")}")

      IO.puts(
        "  Multimodal: #{Map.get(capabilities, :multimodal) || Map.get(capabilities, "multimodal")}"
      )

      IO.puts("  Audio: #{Map.get(capabilities, :audio) || Map.get(capabilities, "audio")}")
      IO.puts("  Code: #{Map.get(capabilities, :code) || Map.get(capabilities, "code")}")
    end

    tier = Map.get(model_info, :tier) || Map.get(model_info, "tier")

    if tier do
      tier_value = Map.get(tier, :value) || Map.get(tier, "value")
      tier_description = Map.get(tier, :description) || Map.get(tier, "description")
      IO.puts("\nTier: #{tier_value} - #{tier_description}")
    end

    pricing_by_provider = Map.get(model_info, :pricing_by_provider) || %{}

    if map_size(pricing_by_provider) > 0 do
      IO.puts("\nPricing by Provider:")

      Enum.each(pricing_by_provider, fn {provider, pricing} ->
        IO.puts("  #{provider}:")
        IO.puts("    Prompt: #{Map.get(pricing, :prompt) || Map.get(pricing, "prompt")}")

        IO.puts(
          "    Completion: #{Map.get(pricing, :completion) || Map.get(pricing, "completion")}"
        )

        if Map.has_key?(pricing, :image) || Map.has_key?(pricing, "image"),
          do: IO.puts("    Image: #{Map.get(pricing, :image) || Map.get(pricing, "image")}")
      end)
    end

    if verbose do
      IO.puts("\nRaw Model Data:")
      IO.puts(inspect(model_info, pretty: true))
    end
  end

  defp list_provider_models(provider_id, opts) do
    verbose = Keyword.get(opts, :verbose, false)
    refresh = Keyword.get(opts, :refresh, false)

    case Provider.get_adapter_by_id(Provider.ensure_atom(provider_id)) do
      {:ok, adapter} ->
        provider = adapter.definition()
        IO.puts("\n--- Models from: #{provider.name} (#{provider.id}) ---")

        list_opts = if refresh, do: [refresh: true], else: []

        case adapter.list_models(list_opts) do
          {:ok, models} ->
            if verbose do
              Enum.each(models, fn model ->
                print_model_details(model)
              end)
            else
              # Just print the model IDs
              Enum.each(models, fn model ->
                IO.puts("  #{model.id}")
              end)
            end

          {:error, reason} ->
            IO.puts("Error listing models: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        list_available_providers()
    end
  end

  defp list_models_from_all_providers(opts) do
    IO.puts("\nListing models from all providers...\n")

    Provider.list()
    |> Enum.each(fn provider ->
      list_provider_models(provider.id, opts)
      IO.puts("\n")
    end)
  end

  defp fetch_all_providers(opts) do
    IO.puts("\nFetching models from all providers...\n")

    Provider.list()
    |> Enum.each(fn provider ->
      fetch_provider_models(provider.id, opts)
      IO.puts("\n")
    end)

    IO.puts("\nAll provider models fetched and cached.\n")
  end

  defp fetch_provider_models(provider_id, opts) do
    verbose = Keyword.get(opts, :verbose, false)
    refresh = Keyword.get(opts, :refresh, false)

    case Provider.get_adapter_by_id(Provider.ensure_atom(provider_id)) do
      {:ok, adapter} ->
        provider = adapter.definition()
        IO.puts("\n--- Fetching models from: #{provider.name} (#{provider.id}) ---")

        # Set refresh option if specified
        list_opts = if refresh, do: [refresh: true], else: []

        case adapter.list_models(list_opts) do
          {:ok, models} ->
            IO.puts("Successfully fetched and cached #{length(models)} models.")

            if verbose do
              IO.puts("\nModel details:")

              Enum.take(models, 5)
              |> Enum.each(fn model ->
                print_model_details(model)
              end)
            else
              # Just print the first few model IDs
              sample = Enum.take(models, 3)
              IO.puts("Sample models: #{Enum.map_join(sample, ", ", & &1.id)}")
            end

            # Verify cache file exists
            models_file =
              Path.join([
                Provider.base_dir(),
                to_string(provider.id),
                "models.json"
              ])

            # Ensure the directory exists
            File.mkdir_p!(Path.dirname(models_file))

            # Save models to file
            json = Jason.encode!(%{"data" => models}, pretty: true)
            File.write!(models_file, json)

            IO.puts("Models cached to: #{models_file}")

            # Now fetch individual model details
            IO.puts("\nFetching detailed information for each model...")
            total = length(models)

            models
            |> Enum.with_index(1)
            |> Enum.each(fn {model, index} ->
              IO.puts("Fetching details for #{model.id} (#{index}/#{total})")
              fetch_specific_model(provider_id, model.id, verbose: verbose, refresh: refresh)
            end)

            IO.puts("\nCompleted fetching all model details.")

          {:error, reason} ->
            IO.puts("Error fetching models: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        list_available_providers()
    end
  end

  defp fetch_specific_model(provider_id, model, opts) do
    verbose = Keyword.get(opts, :verbose, false)
    refresh = Keyword.get(opts, :refresh, false)

    case Provider.get_adapter_by_id(Provider.ensure_atom(provider_id)) do
      {:ok, adapter} ->
        provider = adapter.definition()
        IO.puts("\n--- Fetching model from: #{provider.name} (#{provider.id}) ---")
        IO.puts("Model ID: #{model}")

        # Always set save_to_cache to true and use refresh if specified
        model_opts = [save_to_cache: true, refresh: refresh]

        case adapter.model(model, model_opts) do
          {:ok, model} ->
            IO.puts("Successfully fetched and cached model: #{model.id}")

            if verbose do
              print_model_details(model)
            end

            # Create model file path
            model_file =
              Path.join([
                Provider.base_dir(),
                to_string(provider.id),
                "models",
                "#{model}.json"
              ])

            # Create directory if it doesn't exist
            model_dir = Path.dirname(model_file)
            File.mkdir_p!(model_dir)

            # Save model to file if it doesn't exist
            if not File.exists?(model_file) do
              model_json = Jason.encode!(model, pretty: true)
              File.write!(model_file, model_json)
            end

            IO.puts("Model cached to: #{model_file}")

          {:error, reason} ->
            IO.puts("Error fetching model: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        list_available_providers()
    end
  end

  defp print_model_details(model) do
    model = Map.get(model, :id) || Map.get(model, "id")
    provider = model.provider
    display_name = Map.get(model, :display_name) || Map.get(model, "display_name") || model
    description = Map.get(model, :description) || Map.get(model, "description") || "N/A"
    created_at = Map.get(model, :created_at) || Map.get(model, "created") || "N/A"

    IO.puts("\nModel: #{display_name}")
    IO.puts("ID: #{model}")
    IO.puts("Provider: #{provider}")
    IO.puts("Description: #{description}")
    IO.puts("Created: #{created_at}")

    capabilities = Map.get(model, :capabilities) || Map.get(model, "capabilities")

    if capabilities do
      IO.puts("\nCapabilities:")
      IO.puts("  Chat: #{Map.get(capabilities, :chat) || Map.get(capabilities, "chat")}")

      IO.puts(
        "  Embedding: #{Map.get(capabilities, :embedding) || Map.get(capabilities, "embedding")}"
      )

      IO.puts("  Image: #{Map.get(capabilities, :image) || Map.get(capabilities, "image")}")
      IO.puts("  Vision: #{Map.get(capabilities, :vision) || Map.get(capabilities, "vision")}")

      IO.puts(
        "  Multimodal: #{Map.get(capabilities, :multimodal) || Map.get(capabilities, "multimodal")}"
      )

      IO.puts("  Audio: #{Map.get(capabilities, :audio) || Map.get(capabilities, "audio")}")
      IO.puts("  Code: #{Map.get(capabilities, :code) || Map.get(capabilities, "code")}")
    end

    pricing = Map.get(model, :pricing) || Map.get(model, "pricing")

    if pricing do
      IO.puts("\nPricing:")
      IO.puts("  Prompt: #{Map.get(pricing, :prompt) || Map.get(pricing, "prompt")}")
      IO.puts("  Completion: #{Map.get(pricing, :completion) || Map.get(pricing, "completion")}")

      if Map.has_key?(pricing, :image) || Map.has_key?(pricing, "image"),
        do: IO.puts("  Image: #{Map.get(pricing, :image) || Map.get(pricing, "image")}")
    end

    IO.puts("\nRaw Data:")
    IO.puts(inspect(model, pretty: true))
  end

  defp list_available_providers do
    IO.puts("\nAvailable providers:")

    Provider.list()
    |> Enum.sort_by(& &1.id)
    |> Enum.each(fn provider ->
      IO.puts("  #{provider.id}: #{provider.name} - #{provider.description}")
    end)
  end

  defp show_usage do
    IO.puts("""
    Usage:
      mix jido.ai.cache_models PROVIDER_ID [--verbose] [--refresh]
      mix jido.ai.cache_models PROVIDER_ID --model=MODEL_ID [--verbose] [--refresh]
      mix jido.ai.cache_models --all [--verbose] [--refresh]
      mix jido.ai.cache_models --list-providers

    Examples:
      mix jido.ai.cache_models anthropic
      mix jido.ai.cache_models openai --verbose
      mix jido.ai.cache_models anthropic --model=claude-3-7-sonnet-20250219 --refresh
      mix jido.ai.cache_models --all
    """)
  end
end
