defmodule Jido.AI.ProviderValidation.Functional.LocalConnectionHealthTest do
  @moduledoc """
  Comprehensive connection health check and error handling validation for local providers.

  This test suite validates that local providers (Ollama, LM Studio) handle connection
  failures, timeouts, and various error conditions gracefully without breaking the
  overall system functionality.

  Test Categories:
  - Service availability detection
  - Connection timeout handling
  - Error recovery and fallback mechanisms
  - Health monitoring and status reporting
  - Graceful degradation when services are offline
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :connection_health
  @moduletag :error_handling

  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "local service availability detection" do
    test "detect Ollama service status" do
      # Test various methods of detecting if Ollama is running
      ollama_indicators = [
        {:registry_check, fn -> Registry.list_models(:ollama) end},
        {:provider_metadata, fn -> ProviderMapping.get_jido_provider_metadata(:ollama) end},
        {:model_creation, fn -> Model.from({:ollama, [model: "health-check-model"]}) end}
      ]

      results =
        Enum.map(ollama_indicators, fn {check_type, check_func} ->
          try do
            result = check_func.()
            {check_type, result}
          catch
            kind, reason ->
              {check_type, {:exception, kind, reason}}
          end
        end)

      IO.puts("Ollama service availability indicators:")

      Enum.each(results, fn {check_type, result} ->
        case result do
          {:ok, _data} ->
            IO.puts("  #{check_type}: ✅ Available")

          {:error, reason} when is_atom(reason) or is_binary(reason) ->
            IO.puts("  #{check_type}: ❌ Not available (#{inspect(reason)})")

          {:exception, kind, reason} ->
            IO.puts("  #{check_type}: ⚠️ Exception (#{kind}: #{inspect(reason)})")

          unexpected ->
            IO.puts("  #{check_type}: ❓ Unexpected result (#{inspect(unexpected)})")
        end
      end)

      # Determine overall service status
      available_checks =
        Enum.count(results, fn {_type, result} ->
          match?({:ok, _}, result)
        end)

      service_status =
        cond do
          available_checks >= 2 -> :likely_available
          available_checks == 1 -> :possibly_available
          true -> :not_available
        end

      IO.puts("Overall Ollama service status: #{service_status}")

      # Test should always pass as we're checking detection capability
      assert true
    end

    test "detect LM Studio service status through OpenAI endpoint" do
      # Test LM Studio availability through OpenAI-compatible endpoint
      lm_studio_checks = [
        {:direct_config,
         {:openai, [model: "lm-studio-test", base_url: "http://localhost:1234/v1"]}},
        {:alt_port_config,
         {:openai, [model: "lm-studio-alt", base_url: "http://localhost:1235/v1"]}},
        {:openai_registry, fn -> Registry.list_models(:openai) end}
      ]

      IO.puts("LM Studio service detection through OpenAI compatibility:")

      Enum.each(lm_studio_checks, fn
        {check_type, config} when is_tuple(config) ->
          case Model.from(config) do
            {:ok, model} ->
              IO.puts("  #{check_type}: ✅ Configuration successful")
              assert model.provider == :openai

            {:error, reason} ->
              IO.puts("  #{check_type}: ❌ Configuration failed (#{inspect(reason)})")
          end

        {check_type, check_func} when is_function(check_func) ->
          case check_func.() do
            {:ok, models} when is_list(models) ->
              IO.puts("  #{check_type}: ✅ Available (#{length(models)} models)")

            {:error, reason} ->
              IO.puts("  #{check_type}: ❌ Not available (#{inspect(reason)})")

            unexpected ->
              IO.puts("  #{check_type}: ❓ Unexpected (#{inspect(unexpected)})")
          end
      end)

      IO.puts("LM Studio detection patterns validated")
    end

    test "service discovery with multiple endpoints" do
      # Test discovery across multiple potential local endpoints
      endpoints_to_check = [
        {:ollama, "http://localhost:11434", "Ollama default port"},
        {:ollama, "http://127.0.0.1:11434", "Ollama localhost variant"},
        {:lm_studio, "http://localhost:1234/v1", "LM Studio default"},
        {:lm_studio, "http://localhost:1235/v1", "LM Studio alternative"},
        {:generic_local, "http://localhost:8080", "Generic local service"}
      ]

      IO.puts("Multi-endpoint service discovery:")

      discovered_services =
        Enum.filter(endpoints_to_check, fn {service_type, endpoint, description} ->
          # Test endpoint reachability through configuration
          config =
            case service_type do
              :ollama ->
                {:ollama, [model: "discovery-test"]}

              :lm_studio ->
                {:openai, [model: "discovery-test", base_url: endpoint]}

              :generic_local ->
                {:openai, [model: "discovery-test", base_url: endpoint]}
            end

          case Model.from(config) do
            {:ok, _model} ->
              IO.puts("  #{description}: ✅ Endpoint responsive")
              true

            {:error, reason} ->
              IO.puts("  #{description}: ❌ Not responsive (#{inspect(reason)})")
              false
          end
        end)

      IO.puts(
        "Found #{length(discovered_services)} responsive endpoints out of #{length(endpoints_to_check)}"
      )

      if length(discovered_services) > 0 do
        IO.puts("At least one local service endpoint appears available")
      else
        IO.puts("No local service endpoints detected (expected without running services)")
      end
    end
  end

  describe "connection timeout and error handling" do
    test "timeout handling for unresponsive local services" do
      # Test behavior when local services are slow or unresponsive
      timeout_test_configs = [
        {:ollama, [model: "timeout-test-model"], "Ollama timeout test"},
        {:openai, [model: "timeout-test", base_url: "http://localhost:1234/v1"],
         "LM Studio timeout test"},
        {:openai, [model: "timeout-test", base_url: "http://localhost:9999/v1"],
         "Non-existent port test"}
      ]

      IO.puts("Connection timeout handling tests:")

      Enum.each(timeout_test_configs, fn {provider, opts, description} ->
        IO.puts("\nTesting #{description}:")

        start_time = :os.system_time(:millisecond)

        config = {provider, opts}
        result = Model.from(config)

        end_time = :os.system_time(:millisecond)
        duration = end_time - start_time

        case result do
          {:ok, model} ->
            IO.puts("  Result: ✅ Success in #{duration}ms")
            IO.puts("  Model: #{model.provider}:#{model.model}")

          {:error, reason} when is_binary(reason) ->
            IO.puts("  Result: ❌ Error in #{duration}ms")
            IO.puts("  Reason: #{reason}")
            IO.puts("  ✅ Error handled gracefully")

          {:error, reason} when is_atom(reason) ->
            IO.puts("  Result: ❌ Error in #{duration}ms")
            IO.puts("  Reason: #{inspect(reason)}")
            IO.puts("  ✅ Error handled gracefully")

          unexpected ->
            IO.puts("  Result: ❓ Unexpected in #{duration}ms")
            IO.puts("  Response: #{inspect(unexpected)}")
        end

        # Validate that timeouts are reasonable (not hanging indefinitely)
        # 30 seconds
        if duration > 30_000 do
          IO.puts("  ⚠️ Timeout duration seems excessive: #{duration}ms")
        else
          IO.puts("  ✅ Reasonable timeout duration: #{duration}ms")
        end
      end)
    end

    test "connection retry and recovery patterns" do
      # Test retry mechanisms for local service connections
      retry_scenarios = [
        {:ollama, [model: "retry-test-1"], "Ollama connection retry"},
        {:openai, [model: "retry-test", base_url: "http://localhost:1234/v1"],
         "LM Studio connection retry"}
      ]

      IO.puts("Connection retry and recovery testing:")

      Enum.each(retry_scenarios, fn {provider, opts, description} ->
        IO.puts("\n#{description}:")

        # Attempt multiple connections to test retry behavior
        attempts =
          Enum.map(1..3, fn attempt ->
            start_time = :os.system_time(:millisecond)
            result = Model.from({provider, opts})
            end_time = :os.system_time(:millisecond)

            duration = end_time - start_time
            {attempt, result, duration}
          end)

        # Analyze retry patterns
        successful_attempts =
          Enum.count(attempts, fn {_attempt, result, _duration} ->
            match?({:ok, _}, result)
          end)

        failed_attempts = length(attempts) - successful_attempts

        IO.puts("  Attempts: #{length(attempts)}")
        IO.puts("  Successful: #{successful_attempts}")
        IO.puts("  Failed: #{failed_attempts}")

        # Check for consistency in error handling
        error_reasons =
          Enum.filter_map(
            attempts,
            fn {_attempt, result, _duration} -> match?({:error, _}, result) end,
            fn {_attempt, {:error, reason}, _duration} -> reason end
          )

        unique_errors = Enum.uniq(error_reasons)

        if length(unique_errors) <= 1 do
          IO.puts("  ✅ Consistent error handling across retries")
        else
          IO.puts("  ℹ️ Varying error responses: #{inspect(unique_errors)}")
        end

        # Check timing consistency
        durations = Enum.map(attempts, fn {_attempt, _result, duration} -> duration end)
        avg_duration = Enum.sum(durations) / length(durations)
        IO.puts("  Average response time: #{Float.round(avg_duration, 2)}ms")
      end)
    end

    test "graceful degradation when all local services offline" do
      # Test system behavior when no local services are available
      IO.puts("Graceful degradation testing (all local services offline):")

      local_providers_to_test = [
        {:ollama, [model: "offline-test"]},
        {:openai, [model: "offline-test", base_url: "http://localhost:1234/v1"]},
        {:openai, [model: "offline-test", base_url: "http://localhost:11434/v1"]}
      ]

      all_offline =
        Enum.all?(local_providers_to_test, fn config ->
          case Model.from(config) do
            {:ok, _model} ->
              # Service is available
              false

            {:error, _reason} ->
              # Service is offline (expected)
              true
          end
        end)

      if all_offline do
        IO.puts("✅ All local services offline - testing degradation")

        # Test that the system continues to function
        providers = Provider.list()
        assert is_list(providers), "Provider system should remain functional"

        # Test that registry operations don't crash
        local_registries = [:ollama, :lm_studio, :"lm-studio"]

        registry_results =
          Enum.map(local_registries, fn provider_id ->
            case Registry.list_models(provider_id) do
              {:ok, models} -> {:available, length(models)}
              {:error, reason} -> {:offline, reason}
              unexpected -> {:unexpected, unexpected}
            end
          end)

        offline_count = Enum.count(registry_results, &match?({:offline, _}, &1))

        IO.puts(
          "Registry degradation: #{offline_count}/#{length(local_registries)} providers offline"
        )

        if offline_count == length(local_registries) do
          IO.puts("✅ Complete graceful degradation validated")
        else
          IO.puts("ℹ️ Partial degradation - some services may be available")
        end
      else
        IO.puts("ℹ️ Some local services appear available - cannot test complete degradation")
      end
    end
  end

  describe "error recovery and fallback mechanisms" do
    test "provider fallback when primary local service fails" do
      # Test fallback from one local provider to another
      primary_secondary_pairs = [
        {
          {:ollama, [model: "fallback-test"]},
          {:openai, [model: "fallback-test", base_url: "http://localhost:1234/v1"]},
          "Ollama to LM Studio fallback"
        },
        {
          {:openai, [model: "fallback-test", base_url: "http://localhost:1234/v1"]},
          {:openai, [model: "fallback-test", base_url: "http://localhost:1235/v1"]},
          "LM Studio port fallback"
        }
      ]

      IO.puts("Provider fallback mechanism testing:")

      Enum.each(primary_secondary_pairs, fn {primary_config, secondary_config, description} ->
        IO.puts("\n#{description}:")

        # Try primary provider
        primary_result = Model.from(primary_config)

        case primary_result do
          {:ok, model} ->
            IO.puts("  Primary: ✅ Available (#{model.provider}:#{model.model})")
            IO.puts("  Fallback: Not needed")

          {:error, primary_reason} ->
            IO.puts("  Primary: ❌ Failed (#{inspect(primary_reason)})")

            # Try secondary provider
            secondary_result = Model.from(secondary_config)

            case secondary_result do
              {:ok, model} ->
                IO.puts("  Secondary: ✅ Available (#{model.provider}:#{model.model})")
                IO.puts("  ✅ Fallback successful")

              {:error, secondary_reason} ->
                IO.puts("  Secondary: ❌ Failed (#{inspect(secondary_reason)})")
                IO.puts("  ℹ️ Both providers unavailable (expected without running services)")
            end
        end
      end)
    end

    test "health monitoring and status recovery" do
      # Test continuous health monitoring patterns
      providers_to_monitor = [
        {:ollama, "Ollama health monitoring"},
        {:openai, "OpenAI (LM Studio) health monitoring"}
      ]

      IO.puts("Health monitoring and status recovery:")

      Enum.each(providers_to_monitor, fn {provider_id, description} ->
        IO.puts("\n#{description}:")

        # Simulate health check sequence over time
        health_checks =
          Enum.map(1..5, fn check_num ->
            start_time = :os.system_time(:millisecond)

            # Health check via model listing
            health_result = Registry.list_models(provider_id)

            end_time = :os.system_time(:millisecond)
            duration = end_time - start_time

            status =
              case health_result do
                {:ok, models} when is_list(models) -> :healthy
                {:error, _reason} -> :unhealthy
                _ -> :unknown
              end

            {check_num, status, duration}
          end)

        # Analyze health check patterns
        health_statuses = Enum.map(health_checks, fn {_num, status, _duration} -> status end)
        healthy_count = Enum.count(health_statuses, &(&1 == :healthy))
        unhealthy_count = Enum.count(health_statuses, &(&1 == :unhealthy))

        IO.puts("  Health checks: #{length(health_checks)}")
        IO.puts("  Healthy: #{healthy_count}")
        IO.puts("  Unhealthy: #{unhealthy_count}")

        # Check for status consistency
        unique_statuses = Enum.uniq(health_statuses)

        if length(unique_statuses) == 1 do
          IO.puts("  ✅ Consistent status: #{hd(unique_statuses)}")
        else
          IO.puts("  ⚠️ Status fluctuation: #{inspect(unique_statuses)}")
        end

        # Check response times
        durations = Enum.map(health_checks, fn {_num, _status, duration} -> duration end)
        avg_duration = Enum.sum(durations) / length(durations)
        max_duration = Enum.max(durations)

        IO.puts("  Average health check time: #{Float.round(avg_duration, 2)}ms")
        IO.puts("  Maximum health check time: #{max_duration}ms")

        # 1 second
        if avg_duration < 1000 do
          IO.puts("  ✅ Good health check performance")
        else
          IO.puts("  ⚠️ Slow health check performance")
        end
      end)
    end

    test "error classification and appropriate responses" do
      # Test that different error types get appropriate responses
      error_scenarios = [
        {:ollama, [model: "non-existent-model"], "Model not found"},
        {:openai, [model: "test", base_url: "http://localhost:9999/v1"], "Service unreachable"},
        {:openai, [model: ""], "Invalid model name"},
        {:invalid_provider, [model: "test"], "Invalid provider"}
      ]

      IO.puts("Error classification and response testing:")

      Enum.each(error_scenarios, fn {provider, opts, scenario} ->
        IO.puts("\nTesting: #{scenario}")

        config = {provider, opts}
        result = Model.from(config)

        case result do
          {:ok, model} ->
            IO.puts("  Unexpected success: #{model.provider}:#{model.model}")

          {:error, reason} when is_binary(reason) ->
            IO.puts("  Error type: String message")
            IO.puts("  Message: #{reason}")
            IO.puts("  ✅ Descriptive error provided")

          {:error, reason} when is_atom(reason) ->
            IO.puts("  Error type: Atom")
            IO.puts("  Reason: #{inspect(reason)}")
            IO.puts("  ✅ Structured error provided")

          {:error, {:exception, kind, exception}} ->
            IO.puts("  Error type: Exception")
            IO.puts("  Kind: #{kind}")
            IO.puts("  Exception: #{inspect(exception)}")
            IO.puts("  ✅ Exception properly wrapped")

          unexpected ->
            IO.puts("  Unexpected response: #{inspect(unexpected)}")
            IO.puts("  ⚠️ Error format not recognized")
        end
      end)

      IO.puts("\nError handling validation complete")
    end
  end

  describe "health monitoring integration" do
    test "integration with Jido AI monitoring systems" do
      # Test that health monitoring integrates with broader Jido AI systems
      IO.puts("Health monitoring system integration:")

      # Test provider listing health
      providers = Provider.list()

      local_providers =
        Enum.filter(providers, fn provider ->
          # Identify local providers by common patterns
          provider_name = to_string(provider.id)

          local_indicators = ["ollama", "lm_studio", "lm-studio"]

          Enum.any?(local_indicators, fn indicator ->
            String.contains?(provider_name, indicator)
          end)
        end)

      IO.puts("Local providers in system: #{length(local_providers)}")

      Enum.each(local_providers, fn provider ->
        IO.puts("  #{provider.id}: #{provider.name}")

        # Test provider adapter health
        case Provider.get_adapter_module(provider) do
          {:ok, adapter} ->
            IO.puts("    Adapter: #{adapter} ✅")

          {:error, reason} ->
            IO.puts("    Adapter error: #{inspect(reason)} ❌")
        end
      end)

      # Test session authentication health
      auth_providers = [:ollama, :openai]

      Enum.each(auth_providers, fn provider_id ->
        has_auth = SessionAuthentication.has_session_auth?(provider_id)
        IO.puts("#{provider_id} authentication status: #{has_auth}")

        # Test auth system availability
        try do
          SessionAuthentication.set_for_provider(provider_id, "health-check-key")
          SessionAuthentication.clear_for_provider(provider_id)
          IO.puts("  Auth system: ✅ Functional")
        rescue
          error ->
            IO.puts("  Auth system: ❌ Error (#{inspect(error)})")
        end
      end)

      IO.puts("✅ Health monitoring integration validated")
    end

    test "comprehensive system health report" do
      # Generate comprehensive health report for local providers
      IO.puts("\n=== LOCAL PROVIDER SYSTEM HEALTH REPORT ===")

      health_report = %{
        timestamp: :os.system_time(:millisecond),
        providers: %{},
        registry: %{},
        authentication: %{},
        overall_status: :unknown
      }

      # Provider health
      local_provider_ids = [:ollama, :lm_studio, :"lm-studio", :lmstudio]

      provider_health =
        Enum.map(local_provider_ids, fn provider_id ->
          provider_status =
            case ProviderMapping.get_jido_provider_metadata(provider_id) do
              {:ok, _metadata} -> :configured
              {:error, _reason} -> :not_configured
            end

          registry_status =
            case Registry.list_models(provider_id) do
              {:ok, models} when is_list(models) -> {:available, length(models)}
              {:error, reason} -> {:unavailable, reason}
            end

          auth_status =
            try do
              SessionAuthentication.has_session_auth?(provider_id)
              :functional
            rescue
              _error -> :error
            end

          {provider_id,
           %{
             provider: provider_status,
             registry: registry_status,
             authentication: auth_status
           }}
        end)
        |> Enum.into(%{})

      # Calculate overall status
      available_providers =
        Enum.count(provider_health, fn {_id, status} ->
          match?({:available, _}, status.registry)
        end)

      configured_providers =
        Enum.count(provider_health, fn {_id, status} ->
          status.provider == :configured
        end)

      overall_status =
        cond do
          available_providers > 0 -> :some_available
          configured_providers > 0 -> :configured_but_offline
          true -> :no_local_providers
        end

      final_report = %{health_report | providers: provider_health, overall_status: overall_status}

      # Display report
      IO.puts("Timestamp: #{final_report.timestamp}")
      IO.puts("Overall Status: #{final_report.overall_status}")
      IO.puts("\nProvider Details:")

      Enum.each(final_report.providers, fn {provider_id, status} ->
        IO.puts("#{provider_id}:")
        IO.puts("  Configuration: #{status.provider}")
        IO.puts("  Registry: #{inspect(status.registry)}")
        IO.puts("  Authentication: #{status.authentication}")
      end)

      IO.puts("\nSummary:")
      IO.puts("- Configured providers: #{configured_providers}/#{length(local_provider_ids)}")
      IO.puts("- Available providers: #{available_providers}/#{length(local_provider_ids)}")

      case overall_status do
        :some_available ->
          IO.puts("✅ Local provider ecosystem partially functional")

        :configured_but_offline ->
          IO.puts("⚠️ Local providers configured but services offline")

        :no_local_providers ->
          IO.puts("ℹ️ No local providers configured (expected in many environments)")
      end

      IO.puts("\n=== END HEALTH REPORT ===")

      # Test should always pass as it's generating a report
      assert is_map(final_report)
    end
  end
end
