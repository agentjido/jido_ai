# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)

# Configure ExUnit with very conservative memory settings
# Run tests with minimal concurrency to prevent memory issues
ExUnit.start(
  max_cases: 2,
  # Reduced concurrency to prevent memory leaks
  timeout: 120_000,
  # Longer timeout for integration tests
  # Exclude performance benchmarks, integration tests, tests requiring API keys, and flaky tests by default
  # Integration tests require real API credentials and network connectivity
  # Flaky tests have intermittent failures due to probabilistic assertions
  # Run with: mix test --include integration --include requires_api --include performance_benchmarks --include flaky
  exclude: [:performance_benchmarks, :integration, :requires_api, :flaky]
)

# Global setup to clear cache after each test
# This prevents the 60GB memory leak from model accumulation
ExUnit.after_suite(fn _ ->
  # Note: We can't use after_each at the global level, so cache cleanup
  # happens at module level via on_exit callbacks in test files
  :ok
end)

# Set up global cleanup after all tests complete
ExUnit.after_suite(fn _results ->
  # Final cleanup to release all resources
  try do
    if Process.whereis(Jido.AI.Model.Registry.Cache) do
      Jido.AI.Model.Registry.Cache.clear()
    end
  rescue
    _ -> :ok
  end
end)

if Code.loaded?(Mimic) do
  Mimic.copy(Req)
  Mimic.copy(System)
  Mimic.copy(Finch)
  Mimic.copy(Dotenvy)
  Mimic.copy(Jido.AI.Keyring)
  Mimic.copy(Jido.Exec)
  # GEPA test infrastructure
  Mimic.copy(Jido.AI.Actions.Internal.ChatResponse)
  Mimic.copy(Jido.Agent.Server)
  # ReqLLM integration testing
  Mimic.copy(ReqLLM)
  Mimic.copy(ReqLLM.Model)
  Mimic.copy(ReqLLM.Embedding)
end
