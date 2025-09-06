defmodule ReqAI.CapabilityVerifier do
  @moduledoc """
  Core capability verification engine for ReqAI models.

  Uses ExUnit to dynamically generate and run tests for each capability
  that a model advertises. Provides familiar test output and reporting.

  ## Usage

      ReqAI.CapabilityVerifier.verify("openai:gpt-4o")
      ReqAI.CapabilityVerifier.verify("anthropic:claude-3-sonnet", timeout: 30_000)

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
    with {:ok, model} <- ReqAI.Model.with_metadata(model_id),
         {:ok, capabilities} <- discover_capabilities(model, opts) do
      run_exunit_tests(capabilities, model, opts)
    else
      {:error, reason} ->
        Logger.error("❌ #{reason}")
        :error
    end
  end

  @doc """
  Discovers all capability modules that should be tested for this model.
  """
  @spec discover_capabilities(ReqAI.Model.t(), keyword()) ::
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

  # Auto-discover all capability modules implementing the ReqAI.Capability behaviour
  defp get_all_capability_modules do
    # For now, return known modules. In the future, this could discover modules automatically
    # using :code.all_loaded() and checking for @behaviour ReqAI.Capability
    [
      ReqAI.Capabilities.GenerateText,
      ReqAI.Capabilities.StreamText
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
  Runs ExUnit tests for the given capabilities.
  """
  @spec run_exunit_tests([module()], ReqAI.Model.t(), keyword()) :: :ok | :error
  def run_exunit_tests(capabilities, model, opts) do
    # Configure ExUnit (start returns :already_started if already running)
    # dialyzer complains about unknown function but it exists at runtime
    format = Keyword.get(opts, :format, :pretty)

    # Store formatter options globally for the formatter to access
    formatter_opts =
      case format do
        :json -> [mode: :json]
        :debug -> [mode: :debug]
        :pretty -> [mode: :pretty]
        format when is_binary(format) -> [mode: String.to_atom(format)]
        _ -> [mode: :pretty]
      end

    # Configure the formatter
    ExUnit.configure(formatters: [ReqAI.ExUnit.ModelVerifierFormatter])

    # Put formatter options in Application env for the formatter to access
    Application.put_env(:req_ai, :formatter_opts, formatter_opts)

    _ =
      ExUnit.start(
        autorun: false,
        colors: [enabled: true],
        timeout: Keyword.get(opts, :timeout, 10_000),
        max_failures: if(Keyword.get(opts, :fail_fast, false), do: 1, else: :infinity)
      )

    # Generate test module dynamically - sanitize the model ID for Elixir module name
    model_id = "#{model.provider}:#{model.model}"

    sanitized_model_id =
      model_id
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> Macro.camelize()

    test_module_name = :"ReqAI.CapabilityTest.#{sanitized_model_id}"

    # Build test module using AST manipulation instead of Code.eval_string
    try do
      build_test_module(test_module_name, capabilities, model, opts)
    rescue
      error ->
        Logger.error("❌ Failed to generate tests: #{inspect(error)}")
        :error
    else
      _test_module ->
        # Run the tests
        Logger.info("Verifying #{model_id} capabilities...")
        # dialyzer complains about unknown function but it exists at runtime
        result = ExUnit.run()

        case result do
          %{failures: 0} -> :ok
          _failed -> :error
        end
    end
  end

  # Build test module using AST manipulation (safer than Code.eval_string)
  defp build_test_module(module_name, capabilities, model, opts) do
    model_id = "#{model.provider}:#{model.model}"

    tests =
      for capability_module <- capabilities do
        capability_id = to_string(capability_module.id())
        # Include model ID in test name for the formatter
        test_name = "#{model_id}_#{capability_id}"

        quote do
          test unquote(test_name) do
            case unquote(capability_module).verify(@model, @opts) do
              {:ok, details} ->
                # Test passes, optionally log details
                if @opts[:format] == "debug" do
                  IO.puts("✓ #{inspect(details)}")
                end

                assert true

              {:error, reason} ->
                flunk(unquote("#{capability_id} verification failed: ") <> inspect(reason))
            end
          end
        end
      end

    {:module, module, _binary, _} =
      Module.create(
        module_name,
        quote do
          use ExUnit.Case, async: false

          @model unquote(Macro.escape(model))
          @opts unquote(Macro.escape(opts))

          unquote_splicing(tests)
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end
end
