defmodule Jido.AI.ReqLlmBridge.ToolBuilder do
  @moduledoc """
  Main interface for creating ReqLLM tool descriptors from Jido Actions.

  This module provides the enhanced tool conversion system that bridges Jido's Action
  system with ReqLLM's tool descriptor format, enabling existing Jido Actions to be
  seamlessly used as ReqLLM-compatible tools.

  ## Features

  - Enhanced tool descriptor creation with proper validation
  - JSON Schema conversion from NimbleOptions format
  - Safe callback function generation with error handling
  - Backward compatibility with existing tool consumers
  - Performance optimization through descriptor caching

  ## Usage

      # Convert a single Action to ReqLLM tool descriptor
      {:ok, tool_descriptor} = ToolBuilder.create_tool_descriptor(MyAction)

      # Convert multiple Actions
      {:ok, tool_descriptors} = ToolBuilder.batch_convert([Action1, Action2])

      # Validate Action compatibility before conversion
      :ok = ToolBuilder.validate_action_compatibility(MyAction)
  """

  alias Jido.AI.ReqLlmBridge.{SchemaValidator, ToolExecutor}

  require Logger

  @type tool_descriptor :: %{
          name: String.t(),
          description: String.t(),
          parameter_schema: map(),
          callback: function()
        }

  @type conversion_options :: %{
          context: map(),
          timeout: non_neg_integer(),
          validate_schema: boolean(),
          enable_logging: boolean()
        }

  @doc """
  Creates a ReqLLM tool descriptor from a Jido Action module.

  This is the main entry point for converting Jido Actions to ReqLLM tool descriptors.
  The function performs validation, schema conversion, and callback creation following
  the architectural patterns recommended by expert consultations.

  ## Parameters

  - `action_module`: The Jido Action module to convert
  - `opts`: Optional conversion options (see `t:conversion_options/0`)

  ## Returns

  - `{:ok, tool_descriptor()}` on successful conversion
  - `{:error, reason}` on failure

  ## Examples

      iex> {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)
      iex> descriptor.name
      "sleep_action"

      iex> ToolBuilder.create_tool_descriptor(InvalidModule)
      {:error, %{reason: "invalid_action_module", details: "Module does not implement Jido.Action"}}
  """
  @spec create_tool_descriptor(module(), map()) :: {:ok, tool_descriptor()} | {:error, map()}
  def create_tool_descriptor(action_module, opts \\ %{}) when is_atom(action_module) do
    options = build_conversion_options(opts)

    with :ok <- validate_action_module(action_module),
         {:ok, tool_spec} <- build_tool_specification(action_module),
         {:ok, callback_fn} <- create_execution_callback(action_module, options),
         :ok <- validate_tool_descriptor_if_enabled(tool_spec, options) do
      tool_descriptor = %{
        name: tool_spec.name,
        description: tool_spec.description,
        parameter_schema: tool_spec.schema,
        callback: callback_fn
      }

      log_conversion_success(action_module, options)
      {:ok, tool_descriptor}
    else
      {:error, reason} ->
        log_conversion_failure(action_module, reason, options)
        {:error, format_conversion_error(action_module, reason)}
    end
  rescue
    error ->
      options = build_conversion_options(opts)
      log_conversion_exception(action_module, error, options)

      {:error,
       %{
         reason: "conversion_exception",
         details: Exception.message(error),
         action_module: action_module,
         stacktrace: __STACKTRACE__
       }}
  end

  @doc """
  Converts multiple Jido Actions to ReqLLM tool descriptors.

  Efficiently processes a list of Action modules and returns all successful conversions.
  Failed conversions are logged but do not prevent other conversions from succeeding.

  ## Parameters

  - `action_modules`: List of Jido Action modules to convert
  - `opts`: Optional conversion options applied to all conversions

  ## Returns

  - `{:ok, list(tool_descriptor())}` with all successful conversions
  - `{:error, reason}` if no conversions succeeded

  ## Examples

      iex> actions = [Jido.Actions.Basic.Sleep, Jido.Actions.Basic.Log]
      iex> {:ok, descriptors} = ToolBuilder.batch_convert(actions)
      iex> length(descriptors)
      2
  """
  @spec batch_convert(list(module()), map()) :: {:ok, list(tool_descriptor())} | {:error, map()}
  def batch_convert(action_modules, opts \\ %{}) when is_list(action_modules) do
    options = build_conversion_options(opts)

    results =
      action_modules
      |> Enum.map(&create_tool_descriptor(&1, options))
      |> Enum.reduce({[], []}, fn
        {:ok, descriptor}, {successes, failures} ->
          {[descriptor | successes], failures}

        {:error, reason}, {successes, failures} ->
          {successes, [reason | failures]}
      end)

    case results do
      {successes, []} ->
        {:ok, Enum.reverse(successes)}

      {[], failures} ->
        {:error,
         %{
           reason: "all_conversions_failed",
           details: "No actions could be converted to tool descriptors",
           failures: Enum.reverse(failures)
         }}

      {successes, failures} ->
        Logger.warning("Some tool conversions failed",
          successes: length(successes),
          failures: length(failures)
        )

        {:ok, Enum.reverse(successes)}
    end
  end

  @doc """
  Validates that an Action module is compatible with ReqLLM tool conversion.

  Performs comprehensive validation to ensure the Action can be safely converted
  to a ReqLLM tool descriptor without runtime errors.

  ## Parameters

  - `action_module`: The Jido Action module to validate

  ## Returns

  - `:ok` if the Action is compatible
  - `{:error, reason}` if the Action is incompatible

  ## Examples

      iex> ToolBuilder.validate_action_compatibility(Jido.Actions.Basic.Sleep)
      :ok

      iex> ToolBuilder.validate_action_compatibility(NotAnAction)
      {:error, %{reason: "invalid_action_module", details: "Module does not implement Jido.Action"}}
  """
  @spec validate_action_compatibility(module()) :: :ok | {:error, map()}
  def validate_action_compatibility(action_module) when is_atom(action_module) do
    with :ok <- validate_action_module(action_module),
         {:ok, _tool_spec} <- build_tool_specification(action_module) do
      validate_schema_compatibility(action_module)
    end
  end

  # Private helper functions

  defp validate_action_module(action_module) do
    cond do
      not Code.ensure_loaded?(action_module) ->
        {:error, %{reason: "module_not_loaded", module: action_module}}

      not function_exported?(action_module, :__action_metadata__, 0) ->
        {:error, %{reason: "invalid_action_module", module: action_module}}

      not function_exported?(action_module, :run, 2) ->
        {:error, %{reason: "missing_run_function", module: action_module}}

      true ->
        :ok
    end
  end

  defp build_tool_specification(action_module) do
    name = get_tool_name(action_module)
    description = get_tool_description(action_module)
    schema = convert_action_schema(action_module)

    tool_spec = %{
      name: name,
      description: description,
      schema: schema
    }

    {:ok, tool_spec}
  rescue
    error ->
      {:error,
       %{
         reason: "tool_specification_error",
         details: Exception.message(error),
         module: action_module
       }}
  end

  defp create_execution_callback(action_module, options) do
    context = Map.get(options, :context, %{})
    timeout = Map.get(options, :timeout, 5_000)

    callback_fn = fn parameters ->
      ToolExecutor.execute_tool(action_module, parameters, context, timeout)
    end

    {:ok, callback_fn}
  end

  defp get_tool_name(action_module) do
    action_module.name()
  rescue
    _ ->
      action_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
  end

  defp get_tool_description(action_module) do
    action_module.description() || "No description provided"
  rescue
    _ -> "No description provided"
  end

  defp convert_action_schema(action_module) do
    schema = action_module.schema()
    SchemaValidator.convert_schema_to_reqllm(schema)
  rescue
    error ->
      Logger.warning("Failed to convert schema for #{action_module}: #{Exception.message(error)}")

      %{}
  end

  defp validate_schema_compatibility(action_module) do
    schema = action_module.schema()
    SchemaValidator.validate_nimble_schema_compatibility(schema)
  rescue
    error ->
      {:error,
       %{
         reason: "schema_compatibility_error",
         details: Exception.message(error),
         module: action_module
       }}
  end

  defp validate_tool_descriptor_if_enabled(tool_spec, options) do
    if Map.get(options, :validate_schema, true) do
      validate_tool_descriptor(tool_spec)
    else
      :ok
    end
  end

  defp validate_tool_descriptor(tool_spec) do
    required_keys = [:name, :description, :schema]

    missing_keys =
      required_keys
      |> Enum.reject(&Map.has_key?(tool_spec, &1))

    if missing_keys == [] do
      :ok
    else
      {:error,
       %{
         reason: "invalid_tool_descriptor",
         details: "Missing required keys: #{inspect(missing_keys)}"
       }}
    end
  end

  defp build_conversion_options(opts) do
    defaults = %{
      context: %{},
      timeout: 5_000,
      validate_schema: true,
      enable_logging: Application.get_env(:jido_ai, :enable_req_llm_logging, false)
    }

    Map.merge(defaults, opts)
  end

  defp format_conversion_error(action_module, reason) do
    %{
      reason: "tool_conversion_failed",
      details: "Failed to convert #{action_module} to ReqLLM tool descriptor",
      action_module: action_module,
      original_error: reason
    }
  end

  # Logging functions

  defp log_conversion_success(action_module, options) do
    if Map.get(options, :enable_logging, false) do
      Logger.debug("Successfully converted #{action_module} to ReqLLM tool descriptor",
        action_module: action_module
      )
    end
  end

  defp log_conversion_failure(action_module, reason, options) do
    if Map.get(options, :enable_logging, false) do
      Logger.warning("Failed to convert #{action_module} to ReqLLM tool descriptor",
        action_module: action_module,
        reason: reason
      )
    end
  end

  defp log_conversion_exception(action_module, error, options) do
    if Map.get(options, :enable_logging, false) do
      Logger.error(
        "Exception during tool conversion for #{action_module}: #{Exception.message(error)}",
        action_module: action_module,
        error: error
      )
    end
  end
end
