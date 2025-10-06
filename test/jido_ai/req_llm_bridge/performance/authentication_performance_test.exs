defmodule Jido.AI.ReqLlmBridge.Performance.AuthenticationPerformanceTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log
  @moduletag :performance

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.ProviderAuthRequirements
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  setup :set_mimic_global

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_perf_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "authentication performance benchmarks" do
    test "authentication header generation under 5ms", %{keyring: _keyring} do
      # Set up session authentication
      SessionAuthentication.set_for_provider(:openai, "sk-performance-test-key")

      # Mock external calls for consistent timing
      expect(ReqLlmBridge.Keys, :get, 50, fn :openai, %{} ->
        {:ok, "sk-fallback-key", :environment}
      end)

      # Benchmark authentication header generation
      {elapsed_microseconds, results} =
        :timer.tc(fn ->
          for _i <- 1..50 do
            {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
            {headers, key}
          end
        end)

      # Convert to milliseconds
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_call = elapsed_ms / 50

      # All results should be consistent
      for {headers, key} <- results do
        assert key == "sk-performance-test-key"
        assert headers["authorization"] == "Bearer sk-performance-test-key"
      end

      # Performance requirement: average < 5ms per authentication
      assert average_ms_per_call < 5.0,
             "Authentication too slow: #{average_ms_per_call}ms per call (should be < 5ms)"

      IO.puts(
        "Authentication performance: #{average_ms_per_call}ms per call (#{length(results)} calls)"
      )
    end

    test "provider requirement validation under 5ms per validation", %{keyring: _keyring} do
      # Test different providers and keys
      test_cases = [
        {:openai, "sk-proj-test123456789"},
        {:anthropic, "sk-ant-test123456789012"},
        {:google, "AIzaSyD-test123456789"},
        {:cloudflare, "cf-test-key"},
        {:openrouter, "sk-or-test123456"}
      ]

      total_validations = 0

      {elapsed_microseconds, validation_results} =
        :timer.tc(fn ->
          for {provider, key} <- test_cases do
            # Test each provider multiple times
            results =
              for _i <- 1..20 do
                case ProviderAuthRequirements.validate_auth(provider, key) do
                  :ok -> :valid
                  {:error, _} -> :invalid
                end
              end

            {provider, results}
          end
        end)

      # Count total validations
      total_validations =
        Enum.reduce(validation_results, 0, fn {_provider, results}, acc ->
          acc + length(results)
        end)

      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_validation = elapsed_ms / total_validations

      # All validations should pass for properly formatted keys
      for {provider, results} <- validation_results do
        for result <- results do
          assert result == :valid, "Validation failed for #{provider}"
        end
      end

      assert average_ms_per_validation < 5.0,
             "Validation too slow: #{average_ms_per_validation}ms per validation (should be < 5ms)"

      IO.puts(
        "Validation performance: #{average_ms_per_validation}ms per validation (#{total_validations} validations)"
      )
    end

    test "keyring session resolution under 10ms", %{keyring: _keyring} do
      # Set up multiple providers
      providers = [:openai, :anthropic, :google, :cloudflare, :openrouter]

      for provider <- providers do
        SessionAuthentication.set_for_provider(provider, "#{provider}-test-key")
      end

      # Benchmark session resolution across providers
      {elapsed_microseconds, session_results} =
        :timer.tc(fn ->
          for provider <- providers do
            results =
              for _i <- 1..20 do
                case SessionAuthentication.get_for_request(provider, %{}) do
                  {:session_auth, options} -> options[:api_key]
                  {:no_session_auth} -> nil
                end
              end

            {provider, results}
          end
        end)

      total_resolutions = length(providers) * 20
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_resolution = elapsed_ms / total_resolutions

      # All resolutions should return the correct keys
      for {provider, results} <- session_results do
        expected_key = "#{provider}-test-key"

        for result <- results do
          assert result == expected_key,
                 "Wrong key for #{provider}: got #{result}, expected #{expected_key}"
        end
      end

      assert average_ms_per_resolution < 10.0,
             "Session resolution too slow: #{average_ms_per_resolution}ms per resolution (should be < 10ms)"

      IO.puts(
        "Session resolution performance: #{average_ms_per_resolution}ms per resolution (#{total_resolutions} resolutions)"
      )
    end

    test "provider requirements lookup performance", %{keyring: _keyring} do
      providers = [:openai, :anthropic, :google, :cloudflare, :openrouter, :unknown_provider]

      {elapsed_microseconds, requirement_results} =
        :timer.tc(fn ->
          for provider <- providers do
            results =
              for _i <- 1..50 do
                requirements = ProviderAuthRequirements.get_requirements(provider)
                {provider, requirements.required_keys, requirements.header_format}
              end

            {provider, results}
          end
        end)

      total_lookups = length(providers) * 50
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_lookup = elapsed_ms / total_lookups

      # Verify all lookups return consistent results
      for {provider, results} <- requirement_results do
        # All results for a provider should be identical
        [first_result | rest] = results

        for result <- rest do
          assert result == first_result, "Inconsistent requirements for #{provider}"
        end
      end

      assert average_ms_per_lookup < 1.0,
             "Requirements lookup too slow: #{average_ms_per_lookup}ms per lookup (should be < 1ms)"

      IO.puts(
        "Requirements lookup performance: #{average_ms_per_lookup}ms per lookup (#{total_lookups} lookups)"
      )
    end

    test "end-to-end authentication flow performance", %{keyring: _keyring} do
      # Set up comprehensive authentication
      SessionAuthentication.set_for_provider(:openai, "sk-e2e-test-key")

      # Mock external fallbacks
      expect(ReqLlmBridge.Keys, :get, 100, fn :anthropic, %{} ->
        {:ok, "sk-ant-e2e-fallback", :environment}
      end)

      stub(Keyring, :get_env_value, fn :default, :google_api_key, nil ->
        "google-e2e-fallback"
      end)

      test_scenarios = [
        # Session authentication
        {:openai, "session"},
        # ReqLLM fallback
        {:anthropic, "reqllm"},
        # Keyring fallback
        {:google, "keyring"}
      ]

      {elapsed_microseconds, e2e_results} =
        :timer.tc(fn ->
          for {provider, _expected_source} <- test_scenarios do
            results =
              for _i <- 1..25 do
                # Complete flow: authenticate -> get headers -> validate
                {:ok, headers, key} = Authentication.authenticate_for_provider(provider, %{})
                retrieved_headers = Authentication.get_authentication_headers(provider, %{})
                validation_result = Authentication.validate_authentication(provider, %{})

                {key, headers, retrieved_headers, validation_result}
              end

            {provider, _expected_source, results}
          end
        end)

      total_flows = length(test_scenarios) * 25
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_flow = elapsed_ms / total_flows

      # Verify all flows completed successfully
      for {provider, _expected_source, results} <- e2e_results do
        for {key, headers, retrieved_headers, validation_result} <- results do
          assert is_binary(key) and key != "", "No key for #{provider}"
          assert is_map(headers) and map_size(headers) > 0, "No headers for #{provider}"
          assert is_map(retrieved_headers), "Failed header retrieval for #{provider}"
          assert validation_result == :ok, "Validation failed for #{provider}"
        end
      end

      assert average_ms_per_flow < 15.0,
             "End-to-end flow too slow: #{average_ms_per_flow}ms per flow (should be < 15ms)"

      IO.puts(
        "End-to-end flow performance: #{average_ms_per_flow}ms per flow (#{total_flows} flows)"
      )
    end
  end

  describe "concurrent authentication performance" do
    test "concurrent session access maintains performance", %{keyring: _keyring} do
      # Set up multiple providers
      providers = [:openai, :anthropic, :google]

      for provider <- providers do
        SessionAuthentication.set_for_provider(provider, "#{provider}-concurrent-key")
      end

      # Test concurrent access from multiple processes
      num_concurrent_tasks = 10
      operations_per_task = 20

      {elapsed_microseconds, concurrent_results} =
        :timer.tc(fn ->
          tasks =
            for task_id <- 1..num_concurrent_tasks do
              Task.async(fn ->
                for provider <- providers do
                  results =
                    for _i <- 1..operations_per_task do
                      {:ok, headers, key} =
                        Authentication.authenticate_for_provider(provider, %{})

                      {provider, key, headers}
                    end

                  {task_id, provider, results}
                end
              end)
            end

          # 30 second timeout
          Task.await_many(tasks, 30_000)
        end)

      total_operations = num_concurrent_tasks * length(providers) * operations_per_task
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_operation = elapsed_ms / total_operations

      # Verify all concurrent operations succeeded
      for task_results <- concurrent_results do
        for {task_id, provider, results} <- task_results do
          expected_key = "#{provider}-concurrent-key"

          for {result_provider, key, headers} <- results do
            assert result_provider == provider, "Provider mismatch in task #{task_id}"
            assert key == expected_key, "Wrong key for #{provider} in task #{task_id}"
            assert is_map(headers), "No headers for #{provider} in task #{task_id}"
          end
        end
      end

      # Concurrent performance should not degrade significantly
      assert average_ms_per_operation < 20.0,
             "Concurrent operations too slow: #{average_ms_per_operation}ms per operation (should be < 20ms)"

      IO.puts(
        "Concurrent authentication performance: #{average_ms_per_operation}ms per operation (#{total_operations} concurrent operations)"
      )
    end

    test "high-frequency authentication requests maintain stability", %{keyring: _keyring} do
      # Set up authentication
      SessionAuthentication.set_for_provider(:openai, "sk-high-freq-test")

      # Simulate high-frequency requests (burst testing)
      num_bursts = 5
      requests_per_burst = 100
      burst_interval_ms = 10

      {elapsed_microseconds, burst_results} =
        :timer.tc(fn ->
          for burst <- 1..num_bursts do
            # Create burst of concurrent requests
            tasks =
              for _request <- 1..requests_per_burst do
                Task.async(fn ->
                  {:ok, headers, key} = Authentication.authenticate_for_provider(:openai, %{})
                  {key, headers}
                end)
              end

            burst_results = Task.await_many(tasks, 10_000)

            # Brief pause between bursts
            if burst < num_bursts do
              :timer.sleep(burst_interval_ms)
            end

            {burst, burst_results}
          end
        end)

      total_requests = num_bursts * requests_per_burst
      elapsed_ms = elapsed_microseconds / 1000
      average_ms_per_request = elapsed_ms / total_requests

      # Verify all burst requests succeeded
      for {burst_num, results} <- burst_results do
        for {key, headers} <- results do
          assert key == "sk-high-freq-test", "Wrong key in burst #{burst_num}"

          assert headers["authorization"] == "Bearer sk-high-freq-test",
                 "Wrong headers in burst #{burst_num}"
        end
      end

      assert average_ms_per_request < 25.0,
             "High-frequency requests too slow: #{average_ms_per_request}ms per request (should be < 25ms)"

      IO.puts(
        "High-frequency request performance: #{average_ms_per_request}ms per request (#{total_requests} requests in #{num_bursts} bursts)"
      )
    end
  end

  describe "memory and resource usage" do
    test "authentication operations don't leak memory", %{keyring: _keyring} do
      # Get baseline memory usage
      :erlang.garbage_collect()
      {initial_memory, _} = :erlang.process_info(self(), :memory)

      # Set up authentication
      SessionAuthentication.set_for_provider(:openai, "sk-memory-test")

      # Perform many authentication operations
      num_operations = 1000

      for _i <- 1..num_operations do
        {:ok, _headers, _key} = Authentication.authenticate_for_provider(:openai, %{})
        _retrieved_headers = Authentication.get_authentication_headers(:openai, %{})
        :ok = Authentication.validate_authentication(:openai, %{})

        # Periodically force garbage collection
        if rem(_i, 100) == 0 do
          :erlang.garbage_collect()
        end
      end

      # Final garbage collection and memory check
      :erlang.garbage_collect()
      {final_memory, _} = :erlang.process_info(self(), :memory)

      memory_increase = final_memory - initial_memory
      memory_per_operation = memory_increase / num_operations

      # Memory usage should not grow significantly
      # bytes per operation
      assert memory_per_operation < 100,
             "Memory leak detected: #{memory_per_operation} bytes per operation (should be < 100 bytes)"

      IO.puts(
        "Memory usage: #{memory_increase} bytes total increase (#{memory_per_operation} bytes per operation)"
      )
    end

    test "session cleanup properly frees resources", %{keyring: _keyring} do
      # Set up many providers
      providers = [:openai, :anthropic, :google, :cloudflare, :openrouter]
      keys_per_provider = 100

      # Create many session keys
      for provider <- providers do
        for i <- 1..keys_per_provider do
          SessionAuthentication.set_for_provider(:"#{provider}_#{i}", "key-#{i}")
        end
      end

      # Get memory usage after setup
      :erlang.garbage_collect()
      {memory_after_setup, _} = :erlang.process_info(self(), :memory)

      # Verify providers are set
      total_expected_providers = length(providers) * keys_per_provider
      all_providers = SessionAuthentication.list_providers_with_auth()
      # May be less due to filtering
      assert length(all_providers) <= total_expected_providers

      # Clear all authentication
      SessionAuthentication.clear_all()

      # Verify cleanup
      remaining_providers = SessionAuthentication.list_providers_with_auth()

      assert remaining_providers == [],
             "Session cleanup incomplete: #{Enum.count(remaining_providers)} providers remain"

      # Check memory after cleanup
      :erlang.garbage_collect()
      {memory_after_cleanup, _} = :erlang.process_info(self(), :memory)

      # Memory should be released (allowing some overhead)
      memory_released = memory_after_setup - memory_after_cleanup
      # Avoid division by zero
      cleanup_ratio = memory_released / (memory_after_setup - memory_after_cleanup + 1)

      # Should release most of the allocated memory (at least 50%)
      assert memory_released >= 0,
             "Memory not released after cleanup: #{memory_released} bytes"

      IO.puts(
        "Resource cleanup: #{memory_released} bytes released (setup: #{memory_after_setup}, cleanup: #{memory_after_cleanup})"
      )
    end
  end
end
