# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)

# Configure ExUnit with very conservative memory settings
# Run tests with minimal concurrency to prevent memory issues
ExUnit.start(
  max_cases: 2,
  # Reduced concurrency to prevent memory leaks
  timeout: 120_000,
  # Longer timeout for integration tests
  # Exclude only performance benchmarks by default (real API calls with multiple samples)
  # Provider validation tests now run by default after memory leak fix
  # Run with: mix test --include performance_benchmarks
  exclude: [:performance_benchmarks]
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
  Mimic.copy(OpenaiEx)
  Mimic.copy(OpenaiEx.Chat.Completions)
  Mimic.copy(OpenaiEx.Embeddings)
  Mimic.copy(OpenaiEx.Images)
  Mimic.copy(Dotenvy)
  Mimic.copy(Jido.AI.Keyring)
  Mimic.copy(Jido.Exec)
  Mimic.copy(Jido.AI.Actions.OpenaiEx)
end
