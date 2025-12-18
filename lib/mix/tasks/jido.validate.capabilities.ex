defmodule Mix.Tasks.Jido.Validate.Capabilities do
  @moduledoc """
  Validates capability metadata accuracy across all providers.

  This task checks that capability metadata is correctly populated
  for all models in the registry.

  ## Usage

      mix jido.validate.capabilities
      mix jido.validate.capabilities --provider anthropic
      mix jido.validate.capabilities --verbose

  ## Options

    * `--provider` - Validate only a specific provider
    * `--verbose` - Show detailed validation results
  """

  use Mix.Task
  require Logger

  alias Jido.AI.Model.Registry

  @shortdoc "Validates capability metadata across all providers"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [provider: :string, verbose: :boolean],
        aliases: [p: :provider, v: :verbose]
      )

    provider = opts[:provider] && String.to_atom(opts[:provider])
    verbose = opts[:verbose] || false

    Mix.shell().info("=== Capability Metadata Validation ===\n")

    case Registry.list_models(provider) do
      {:ok, models} ->
        validate_models(models, verbose)

      {:error, reason} ->
        Mix.shell().error("Failed to list models: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp validate_models(models, verbose) do
    total = length(models)
    Mix.shell().info("Validating #{total} models...\n")

    results =
      Enum.reduce(
        models,
        %{valid: 0, missing_capabilities: 0, invalid_format: 0, providers: %{}},
        fn model, acc ->
          model_id = Map.get(model, :id) || Map.get(model, "id") || "unknown"
          provider = Map.get(model, :provider) || Map.get(model, "provider") || :unknown

          # Update provider count
          provider_stats = Map.get(acc.providers, provider, %{total: 0, valid: 0})
          provider_stats = Map.update!(provider_stats, :total, &(&1 + 1))

          result =
            cond do
              # Check for missing capabilities
              is_nil(Map.get(model, :capabilities)) and is_nil(Map.get(model, "capabilities")) ->
                if verbose do
                  Mix.shell().info("  ⚠️  #{model_id}: Missing capabilities field")
                end

                provider_stats = Map.put(acc.providers, provider, provider_stats)

                %{
                  acc
                  | missing_capabilities: acc.missing_capabilities + 1,
                    providers: provider_stats
                }

              # Check for invalid format
              not valid_capabilities_format?(model) ->
                if verbose do
                  Mix.shell().info("  ❌ #{model_id}: Invalid capabilities format")
                end

                provider_stats = Map.put(acc.providers, provider, provider_stats)
                %{acc | invalid_format: acc.invalid_format + 1, providers: provider_stats}

              # Valid
              true ->
                if verbose do
                  caps = Map.get(model, :capabilities) || Map.get(model, "capabilities")
                  Mix.shell().info("  ✅ #{model_id}: #{format_capabilities(caps)}")
                end

                provider_stats = Map.update!(provider_stats, :valid, &(&1 + 1))
                provider_stats = Map.put(acc.providers, provider, provider_stats)
                %{acc | valid: acc.valid + 1, providers: provider_stats}
            end

          result
        end
      )

    print_summary(results, total)
  end

  defp valid_capabilities_format?(model) do
    caps = Map.get(model, :capabilities) || Map.get(model, "capabilities")

    is_map(caps) and
      Enum.all?(caps, fn
        {key, value} when is_atom(key) or is_binary(key) ->
          is_boolean(value) or is_binary(value) or is_atom(value)

        _ ->
          false
      end)
  end

  defp format_capabilities(caps) when is_map(caps) do
    caps
    |> Enum.filter(fn {_k, v} -> v == true end)
    |> Enum.map_join(", ", fn {k, _v} -> to_string(k) end)
  end

  defp format_capabilities(_), do: "none"

  defp print_summary(results, total) do
    Mix.shell().info("\n=== Validation Summary ===")
    Mix.shell().info("Total models: #{total}")
    Mix.shell().info("✅ Valid: #{results.valid} (#{percentage(results.valid, total)}%)")

    Mix.shell().info(
      "⚠️  Missing capabilities: #{results.missing_capabilities} (#{percentage(results.missing_capabilities, total)}%)"
    )

    Mix.shell().info(
      "❌ Invalid format: #{results.invalid_format} (#{percentage(results.invalid_format, total)}%)"
    )

    Mix.shell().info("\n=== By Provider ===")

    results.providers
    |> Enum.sort_by(fn {provider, _} -> provider end)
    |> Enum.each(fn {provider, stats} ->
      Mix.shell().info(
        "  #{provider}: #{stats.valid}/#{stats.total} valid (#{percentage(stats.valid, stats.total)}%)"
      )
    end)

    accuracy = percentage(results.valid, total)

    Mix.shell().info("\n=== Overall Accuracy: #{accuracy}% ===")

    if accuracy >= 95.0 do
      Mix.shell().info("✅ Target accuracy (>95%) achieved!")
      :ok
    else
      Mix.shell().error("❌ Below target accuracy of 95%")
      exit({:shutdown, 1})
    end
  end

  defp percentage(_, 0), do: 0.0
  defp percentage(count, total), do: Float.round(count / total * 100, 1)
end
