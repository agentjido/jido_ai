defmodule ReqLLM.Capability do
  @moduledoc """
  Core capability verification engine for ReqLLM models.

  Direct verification runner for model capabilities without ExUnit dependencies.
  Provides clean output and reporting through the Reporter system.

  ## Usage

      ReqLLM.Capability.verify("openai:gpt-4o")
      ReqLLM.Capability.verify("anthropic:claude-3-sonnet", timeout: 30_000)

  """

  require Logger

  @doc """
  Verifies all advertised capabilities for the given model.

  ## Parameters

    * `model_id` - The model identifier (e.g., "openai:gpt-4o")
    * `opts` - Options including:
      * `:timeout` - Request timeout in milliseconds (default: 10_000)
      * `:only` - List of capability atoms to test (default: all advertised)
      * `:format` - Output format (:pretty, :json, :debug)
      * `:fail_fast` - Stop on first failure (default: false)

  ## Returns

    * `:ok` - All capabilities passed
    * `:error` - At least one capability failed

  """
  @spec verify(String.t(), keyword()) :: :ok | :error
  def verify(model_id, opts \\ []) do
    with {:ok, model} <- ReqLLM.Model.with_metadata(model_id),
         {:ok, capabilities} <- discover_capabilities(model, opts) do
      results = run_checks(capabilities, model, opts)

      # Use reporter for output
      ReqLLM.Capability.Reporter.dispatch(results, opts)

      # Return success if all checks passed
      if Enum.all?(results, &(&1.status == :passed)) do
        :ok
      else
        :error
      end
    else
      {:error, reason} ->
        Logger.error("❌ #{reason}")
        :error
    end
  end

  @doc """
  Discovers all capability modules that should be tested for this model.
  """
  @spec discover_capabilities(ReqLLM.Model.t(), keyword()) ::
          {:ok, [module()]} | {:error, String.t()}
  def discover_capabilities(model, opts) do
    capability_modules = get_all_capability_modules()

    # Filter to only capabilities advertised by the model
    advertised_capabilities =
      capability_modules
      |> Enum.filter(&capability_advertised?(&1, model))

    # Further filter by --only option if provided
    capabilities =
      case Keyword.get(opts, :only) do
        nil ->
          advertised_capabilities

        only_list when is_list(only_list) ->
          only_atoms = Enum.map(only_list, &to_existing_atom_safe/1) |> Enum.reject(&is_nil/1)
          Enum.filter(advertised_capabilities, fn mod -> mod.id() in only_atoms end)

        only_string when is_binary(only_string) ->
          only_atoms =
            only_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&to_existing_atom_safe/1)
            |> Enum.reject(&is_nil/1)

          Enum.filter(advertised_capabilities, fn mod -> mod.id() in only_atoms end)
      end

    model_id = "#{model.provider}:#{model.model}"

    case capabilities do
      [] -> {:error, "No capabilities to verify for model #{model_id}"}
      caps -> {:ok, caps}
    end
  end

  # Auto-discover all capability modules implementing the ReqLLM.Capability.Adapter behaviour
  defp get_all_capability_modules do
    # For now, return known modules. In the future, this could discover modules automatically
    # using :code.all_loaded() and checking for @behaviour ReqLLM.Capability.Adapter
    [
      ReqLLM.Capability.GenerateText,
      ReqLLM.Capability.StreamText,
      ReqLLM.Capability.ToolCalling,
      ReqLLM.Capability.Reasoning
    ]
  end

  # Check if a capability is advertised by the model
  defp capability_advertised?(capability_module, model) do
    try do
      capability_module.advertised?(model)
    catch
      # Catch all error types including throw, exit, and error
      kind, reason ->
        Logger.warning(
          "Error checking if #{inspect(capability_module)} is advertised: #{kind}: #{inspect(reason)}"
        )

        false
    end
  end

  # Convert string to existing atom safely, returning nil if atom doesn't exist
  defp to_existing_atom_safe(value) when is_atom(value), do: value

  defp to_existing_atom_safe(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  @doc """
  Runs capability checks for the given capabilities.
  """
  @spec run_checks([module()], ReqLLM.Model.t(), keyword()) :: [ReqLLM.Capability.Result.t()]
  def run_checks(capabilities, model, opts) do
    model_id = "#{model.provider}:#{model.model}"
    fail_fast = Keyword.get(opts, :fail_fast, false)

    Logger.info("Verifying #{model_id} capabilities...")

    {results, _should_stop} =
      Enum.reduce_while(capabilities, {[], false}, fn capability_module, {acc, _stop} ->
        capability_id = capability_module.id()

        {latency_ms, verify_result} =
          :timer.tc(fn ->
            capability_module.verify(model, opts)
          end)

        # Convert microseconds to milliseconds
        latency_ms = div(latency_ms, 1000)

        result =
          case verify_result do
            {:ok, details} ->
              ReqLLM.Capability.Result.passed(model_id, capability_id, latency_ms, details)

            {:error, reason} ->
              ReqLLM.Capability.Result.failed(model_id, capability_id, latency_ms, reason)
          end

        new_acc = [result | acc]

        # Check if we should stop early due to fail_fast
        if fail_fast and result.status == :failed do
          {:halt, {new_acc, true}}
        else
          {:cont, {new_acc, false}}
        end
      end)

    # Return results in reverse order (since we built them with prepend)
    Enum.reverse(results)
  end
end
