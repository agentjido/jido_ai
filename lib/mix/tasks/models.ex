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

    # Parse arguments with enhanced registry support
    {opts, args, _} = parse_args_enhanced(args)

    # Convert opts list to map for easier access
    opts_map = Enum.into(opts, %{})

    verbose = Keyword.get(opts, :verbose, false)
    refresh = Keyword.get(opts, :refresh, false)
    specific_model = Keyword.get(opts, :model)

    cond do
      # Help command
      opts_map[:help] ->
        show_help_enhanced()

      # Registry commands
      handle_registry_stats(opts_map) ->
        :ok

      handle_enhanced_listing(opts_map) ->
        :ok

      # Legacy commands
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
        show_help_enhanced()
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
        Provider.standardize_model_name(model)
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

    providers =
      Provider.list()
      |> Enum.sort_by(& &1.id)

    # Group providers by implementation status
    {legacy_providers, reqllm_providers} =
      Enum.split_with(providers, fn provider ->
        # Check if provider has a legacy adapter
        provider.id in [:openai, :anthropic, :google, :cloudflare, :openrouter]
      end)

    # Show legacy providers first
    if length(legacy_providers) > 0 do
      IO.puts("\nFully Implemented (Legacy Adapters):")

      Enum.each(legacy_providers, fn provider ->
        IO.puts("  ✓ #{provider.id}: #{provider.name} - #{provider.description}")
      end)
    end

    # Show ReqLLM-backed providers
    if length(reqllm_providers) > 0 do
      IO.puts("\nAvailable via ReqLLM Integration:")

      reqllm_providers
      # Show first 20 to avoid overwhelming output
      |> Enum.take(20)
      |> Enum.each(fn provider ->
        status =
          if ReqLLM.Provider.Registry.implemented?(provider.id),
            do: "✓",
            else: "○"

        IO.puts("  #{status} #{provider.id}: #{provider.name}")
      end)

      remaining = length(reqllm_providers) - 20

      if remaining > 0 do
        IO.puts("  ... and #{remaining} more providers")
      end
    end

    IO.puts("\n✓ = Fully implemented, ○ = Metadata only")
    IO.puts("Total providers available: #{length(providers)}")
  end

  # Registry-enhanced functionality

  defp handle_registry_stats(args) do
    if args[:registry_stats] do
      display_registry_statistics()
      true
    else
      false
    end
  end

  defp handle_enhanced_listing(args) do
    cond do
      args[:list_all_models_enhanced] ->
        display_enhanced_all_models(args)
        true

      args[:list_models_enhanced] ->
        provider = get_provider_from_args(args)
        display_enhanced_provider_models(provider, args)
        true

      args[:discover_models] ->
        filters = build_filters_from_args(args)
        display_discovered_models(filters, args)
        true

      true ->
        false
    end
  end

  defp display_registry_statistics do
    Mix.shell().info("Registry Statistics:\n")

    case Provider.get_model_registry_stats() do
      {:ok, stats} ->
        Mix.shell().info("Total Models: #{stats.total_models}")
        Mix.shell().info("Registry Models: #{Map.get(stats, :registry_models, 0)}")
        Mix.shell().info("Cached Models: #{Map.get(stats, :cached_models, 0)}")
        Mix.shell().info("Total Providers: #{stats.total_providers}")

        if registry_health = Map.get(stats, :registry_health) do
          status = Map.get(registry_health, :status, :unknown)
          Mix.shell().info("Registry Status: #{status}")

          if response_time = Map.get(registry_health, :response_time_ms) do
            Mix.shell().info("Registry Response Time: #{response_time}ms")
          end
        end

        Mix.shell().info("\nProvider Coverage:")

        stats.provider_coverage
        |> Enum.sort_by(fn {_provider, count} -> count end, :desc)
        |> Enum.each(fn {provider, count} ->
          Mix.shell().info("  #{provider}: #{count} models")
        end)

        if capabilities = Map.get(stats, :capabilities_distribution) do
          Mix.shell().info("\nCapability Distribution:")

          capabilities
          |> Enum.sort_by(fn {_capability, count} -> count end, :desc)
          |> Enum.each(fn {capability, count} ->
            Mix.shell().info("  #{capability}: #{count} models")
          end)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to get registry statistics: #{inspect(reason)}")
    end
  end

  defp display_enhanced_all_models(args) do
    verbose = args[:verbose] || false
    source = get_source_option(args)

    Mix.shell().info("Enhanced Model Listing (source: #{source}):\n")

    case Provider.list_all_models_enhanced(nil, source: source) do
      {:ok, models} ->
        Mix.shell().info("Found #{length(models)} models")

        if verbose do
          display_models_verbose(models)
        else
          display_models_summary(models)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to list enhanced models: #{inspect(reason)}")
    end
  end

  defp display_enhanced_provider_models(provider, args) do
    verbose = args[:verbose] || false
    source = get_source_option(args)

    Mix.shell().info("Enhanced #{provider} Models (source: #{source}):\n")

    case Provider.list_all_models_enhanced(provider, source: source) do
      {:ok, models} ->
        Mix.shell().info("Found #{length(models)} models for #{provider}")

        if verbose do
          display_models_verbose(models)
        else
          display_models_summary(models)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to list enhanced models for #{provider}: #{inspect(reason)}")
    end
  end

  defp display_discovered_models(filters, args) do
    verbose = args[:verbose] || false

    Mix.shell().info("Model Discovery with filters: #{inspect(filters)}\n")

    case Provider.discover_models_by_criteria(filters) do
      {:ok, models} ->
        Mix.shell().info("Found #{length(models)} models matching criteria")

        if verbose do
          display_models_verbose(models)
        else
          display_models_summary(models)
        end

      {:error, reason} ->
        Mix.shell().error("Model discovery failed: #{inspect(reason)}")
    end
  end

  defp display_models_verbose(models) do
    models
    |> Enum.each(fn model ->
      provider = Map.get(model, :provider) || Map.get(model, "provider")
      id = Map.get(model, :id) || Map.get(model, "id")
      name = Map.get(model, :name) || Map.get(model, "name") || id

      Mix.shell().info("#{provider}:#{id}")
      Mix.shell().info("  Name: #{name}")

      if description = Map.get(model, :description) || Map.get(model, "description") do
        Mix.shell().info("  Description: #{description}")
      end

      if capabilities = Map.get(model, :capabilities) do
        Mix.shell().info("  Capabilities: #{format_capabilities(capabilities)}")
      end

      if limit = Map.get(model, :limit) do
        Mix.shell().info("  Context: #{Map.get(limit, :context, "unknown")}")
        Mix.shell().info("  Max Output: #{Map.get(limit, :output, "unknown")}")
      end

      if cost = Map.get(model, :cost) do
        Mix.shell().info(
          "  Cost: input=$#{Map.get(cost, :input, "?")}/1M, output=$#{Map.get(cost, :output, "?")}/1M"
        )
      end

      if reqllm_id = Map.get(model, :reqllm_id) do
        Mix.shell().info("  ReqLLM ID: #{reqllm_id}")
      end

      Mix.shell().info("")
    end)
  end

  defp display_models_summary(models) do
    # Group by provider
    provider_groups =
      Enum.group_by(models, fn model ->
        Map.get(model, :provider) || Map.get(model, "provider")
      end)

    provider_groups
    |> Enum.sort_by(fn {provider, _models} -> provider end)
    |> Enum.each(fn {provider, provider_models} ->
      Mix.shell().info("#{provider}: #{length(provider_models)} models")

      # Show first few models as examples
      provider_models
      |> Enum.take(5)
      |> Enum.each(fn model ->
        id = Map.get(model, :id) || Map.get(model, "id")
        capabilities = format_capabilities_short(Map.get(model, :capabilities))
        Mix.shell().info("  - #{id}#{capabilities}")
      end)

      if length(provider_models) > 5 do
        Mix.shell().info("  ... and #{length(provider_models) - 5} more")
      end

      Mix.shell().info("")
    end)
  end

  defp format_capabilities(nil), do: "none specified"

  defp format_capabilities(caps) when is_map(caps) do
    enabled_caps =
      caps
      |> Enum.filter(fn {_cap, enabled} -> enabled end)
      |> Enum.map(fn {cap, _} -> cap end)

    if length(enabled_caps) > 0 do
      Enum.join(enabled_caps, ", ")
    else
      "none"
    end
  end

  defp format_capabilities_short(nil), do: ""

  defp format_capabilities_short(caps) when is_map(caps) do
    flags = []
    flags = if Map.get(caps, :tool_call), do: ["T" | flags], else: flags
    flags = if Map.get(caps, :reasoning), do: ["R" | flags], else: flags
    flags = if Map.get(caps, :attachment), do: ["A" | flags], else: flags

    if length(flags) > 0 do
      " [#{Enum.join(flags, "")}]"
    else
      ""
    end
  end

  defp get_source_option(args) do
    cond do
      args[:registry_only] -> :registry
      args[:cache_only] -> :cache
      true -> :both
    end
  end

  defp build_filters_from_args(args) do
    filters = []

    filters =
      if capability = args[:capability] do
        [{:capability, String.to_atom(capability)} | filters]
      else
        filters
      end

    filters =
      if max_cost = args[:max_cost] do
        [{:max_cost_per_token, String.to_float(max_cost)} | filters]
      else
        filters
      end

    filters =
      if min_context = args[:min_context] do
        [{:min_context_length, String.to_integer(min_context)} | filters]
      else
        filters
      end

    filters =
      if provider = args[:provider_filter] do
        [{:provider, String.to_atom(provider)} | filters]
      else
        filters
      end

    filters =
      if modality = args[:modality] do
        [{:modality, String.to_atom(modality)} | filters]
      else
        filters
      end

    filters
  end

  defp get_provider_from_args(args) do
    # This would need to be enhanced to get provider from command line args
    # For now, return nil to list all providers
    args[:provider] || nil
  end

  # Enhanced argument parsing
  defp parse_args_enhanced(args) do
    args
    |> OptionParser.parse(
      switches: [
        # Existing switches...
        help: :boolean,
        list_providers: :boolean,
        list_all_models: :boolean,
        verbose: :boolean,
        fetch: :boolean,
        model: :string,
        refresh: :boolean,
        show: :string,
        compare: :string,

        # New registry switches
        registry_stats: :boolean,
        list_all_models_enhanced: :boolean,
        list_models_enhanced: :boolean,
        discover_models: :boolean,
        registry_only: :boolean,
        cache_only: :boolean,
        capability: :string,
        max_cost: :string,
        min_context: :string,
        provider_filter: :string,
        modality: :string
      ],
      aliases: [
        h: :help,
        v: :verbose,
        f: :fetch,
        m: :model,
        r: :refresh,
        s: :show,
        c: :compare,
        # New aliases
        rs: :registry_stats,
        lae: :list_all_models_enhanced,
        lme: :list_models_enhanced,
        dm: :discover_models
      ]
    )
  end

  # Update help text to include new registry commands
  defp show_help_enhanced do
    Mix.shell().info("""
    Jido AI Models Management (Enhanced with Registry)

    USAGE:
        mix jido.ai.models [OPTIONS]
        mix jido.ai.models PROVIDER [OPTIONS]

    REGISTRY COMMANDS:
        --registry-stats, -rs           Show comprehensive registry statistics
        --list-all-models-enhanced      List all models using registry + cache
        --list-models-enhanced          List provider models using registry + cache
        --discover-models, -dm          Discover models with advanced filtering

    REGISTRY OPTIONS:
        --registry-only                 Use only registry data (no cache)
        --cache-only                    Use only cached data (no registry)
        --capability CAPABILITY         Filter by capability (tool_call, reasoning, etc.)
        --max-cost COST                 Maximum cost per token (e.g., "0.001")
        --min-context LENGTH            Minimum context length (e.g., "100000")
        --provider-filter PROVIDER      Filter by specific provider
        --modality MODALITY             Filter by modality (text, image, audio)

    REGISTRY EXAMPLES:
        # Show comprehensive registry statistics
        mix jido.ai.models --registry-stats

        # List all models from registry and cache
        mix jido.ai.models --list-all-models-enhanced

        # List only registry models for Anthropic
        mix jido.ai.models anthropic --list-models-enhanced --registry-only

        # Find models with tool calling capability
        mix jido.ai.models --discover-models --capability tool_call

        # Find cost-effective models with large context
        mix jido.ai.models --discover-models --max-cost 0.0005 --min-context 100000

        # Find Anthropic models with reasoning capability
        mix jido.ai.models --discover-models --provider-filter anthropic --capability reasoning

    LEGACY COMMANDS:
        --list-providers                List all available providers
        --list-all-models               List all cached models
        --fetch, -f                     Fetch and cache models
        --show MODEL, -s MODEL          Show detailed model information
        --compare MODEL, -c MODEL       Compare model across providers
        --verbose, -v                   Show detailed output
        --help, -h                      Show this help

    PROVIDERS:
        anthropic, openai, google, cloudflare, openrouter

    For more information, visit: https://docs.jido.ai
    """)
  end
end
