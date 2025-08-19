defmodule Jido.AI.TestUtils do
  @moduledoc """
  Test support utilities for the JidoAI package.

  Provides helpers for:
  - Isolated Keyring setup/teardown
  - Provider registry management
  - Common test fixtures
  - HTTP mocking helpers using Req.Test
  """

  ## Keyring Test Utilities - DEPRECATED
  ## Use Jido.AI.TestSupport.KeyringCase instead
  alias Jido.AI.Keyring
  alias Jido.AI.Test.Fixtures.ProviderFixtures

  @doc """
  Sets up an isolated keyring for testing.
  Clears any existing keys and returns a cleanup function.

  DEPRECATED: Use `use Jido.AI.TestSupport.KeyringCase` instead.
  """
  def setup_isolated_keyring do
    # Clear any existing keys
    Keyring.clear_all_session_values()

    # Return cleanup function
    fn -> Keyring.clear_all_session_values() end
  end

  ## Provider Registry Management

  @doc """
  Clears the provider registry by removing persistent_term data.
  Use this to ensure clean state between tests.
  """
  def clear_provider_registry do
    # Clear all persistent terms related to providers
    :persistent_term.erase({Provider.Registry, :providers})
    :persistent_term.erase({Provider.Registry, :initialized})
  end

  @doc """
  Resets the provider registry to a clean state.
  Returns a cleanup function that can be called in on_exit.
  """
  def reset_provider_registry do
    # Store current state
    current_providers = :persistent_term.get({Provider.Registry, :providers}, %{})
    current_initialized = :persistent_term.get({Provider.Registry, :initialized}, false)

    # Clear registry
    clear_provider_registry()

    # Return cleanup function to restore state
    fn ->
      if current_initialized do
        :persistent_term.put({Provider.Registry, :providers}, current_providers)
        :persistent_term.put({Provider.Registry, :initialized}, current_initialized)
      end
    end
  end

  ## Test Fixtures (use fixture modules instead)

  # Import fixture modules for models and providers
  # Use Jido.AI.Test.Fixtures.ModelFixtures for model creation
  # Use Jido.AI.Test.Fixtures.ProviderFixtures for provider creation and responses

  ## HTTP Mocking Helpers - DEPRECATED
  ## Use Jido.AI.TestSupport.HTTPCase instead

  # HTTP Response helpers - use Jido.AI.Test.Fixtures.ProviderFixtures instead
  # These are kept for backward compatibility during the transition

  @doc """
  Returns a mock success response data structure.
  Use ProviderFixtures.success_response/1 instead.
  """
  def mock_success_response do
    ProviderFixtures.success_response()
  end

  @doc """
  Returns a mock OpenAI chat completion response.
  Use ProviderFixtures.openai_json/2 instead.
  """
  def mock_openai_response(content \\ "Test response") do
    ProviderFixtures.openai_json(content)
  end

  @doc """
  Returns a mock Anthropic message response.
  Use ProviderFixtures.anthropic_json/2 instead.
  """
  def mock_anthropic_response(content \\ "Test response") do
    ProviderFixtures.anthropic_json(content)
  end

  @doc """
  Returns a mock Google Gemini response.
  Use ProviderFixtures.gemini_json/2 instead.
  """
  def mock_gemini_response(content \\ "Test response") do
    ProviderFixtures.gemini_json(content)
  end

  ## Test Assertion Helpers - DEPRECATED
  ## Use Jido.AI.TestSupport.Assertions instead

  @doc """
  Waits for a process to complete or timeout.
  Useful for testing async operations.
  """
  def wait_for_completion(pid, timeout \\ 5000) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  ## Memory and Resource Helpers

  @doc """
  Captures process memory usage before and after a function execution.
  Returns {result, memory_diff_kb}.
  """
  def measure_memory(fun) when is_function(fun, 0) do
    {memory_before, _} = :erlang.process_info(self(), :memory)
    result = fun.()
    {memory_after, _} = :erlang.process_info(self(), :memory)

    memory_diff_kb = div(memory_after - memory_before, 1024)
    {result, memory_diff_kb}
  end

  @doc """
  Times the execution of a function in milliseconds.
  Returns {result, time_ms}.
  """
  def measure_time(fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)

    {result, end_time - start_time}
  end
end
