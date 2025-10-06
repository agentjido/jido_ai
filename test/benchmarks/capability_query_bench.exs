defmodule Jido.AI.Benchmarks.CapabilityQueryBench do
  @moduledoc """
  Performance benchmarks for capability querying.

  Measures baseline performance before optimization and validates
  improvements after implementing capability indexing and caching.

  Run with: mix run test/benchmarks/capability_query_bench.exs
  """

  alias Jido.AI.Model.Registry

  # Benchmark configuration
  @benchmark_time 5
  @warmup_time 2

  def run do
    IO.puts("\n=== Capability Query Performance Benchmarks ===\n")

    # Ensure registry is warmed up
    {:ok, _models} = Registry.list_models()

    Benchee.run(
      %{
        "list_all_models" => fn ->
          {:ok, _models} = Registry.list_models()
        end,
        "list_provider_models" => fn ->
          {:ok, _models} = Registry.list_models(:anthropic)
        end,
        "discover_with_capability" => fn ->
          {:ok, _models} = Registry.discover_models(capability: :tool_call)
        end,
        "discover_with_multiple_filters" => fn ->
          {:ok, _models} =
            Registry.discover_models(
              capability: :tool_call,
              min_context_length: 100_000
            )
        end,
        "discover_with_cost_filter" => fn ->
          {:ok, _models} = Registry.discover_models(max_cost_per_token: 0.001)
        end,
        "discover_with_modality" => fn ->
          {:ok, _models} = Registry.discover_models(modality: :text)
        end,
        "discover_with_tier" => fn ->
          {:ok, _models} = Registry.discover_models(tier: :premium)
        end,
        "get_specific_model" => fn ->
          {:ok, _model} = Registry.get_model(:anthropic, "claude-3-5-sonnet-20241022")
        end,
        "get_registry_stats" => fn ->
          {:ok, _stats} = Registry.get_registry_stats()
        end
      },
      time: @benchmark_time,
      warmup: @warmup_time,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )

    IO.puts("\n=== Performance Targets ===")
    IO.puts("  Simple capability filter: < 5ms (p95)")
    IO.puts("  Complex multi-filter query: < 10ms (p95)")
    IO.puts("  Full model list: < 100ms (p95)")
    IO.puts("\nRun this benchmark again after optimization to verify improvements.\n")
  end
end

# Run benchmarks if this file is executed directly
if System.get_env("MIX_ENV") in ["dev", "test"] do
  Jido.AI.Benchmarks.CapabilityQueryBench.run()
end
