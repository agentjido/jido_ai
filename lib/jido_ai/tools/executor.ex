defmodule Jido.AI.Tools.Executor do
  @moduledoc """
  Action execution with validation, error handling, and timeout support.

  This module provides a single entry point for executing Jido.Action modules
  as LLM tools. It handles the full execution lifecycle:

  1. **Tool Lookup**: Finds the action by name in the provided tools map
  2. **Parameter Normalization**: Converts LLM arguments to proper types
  3. **Execution**: Dispatches to Jido.Exec
  4. **Result Formatting**: Converts results to LLM-friendly format
  5. **Error Handling**: Catches exceptions and returns structured errors
  6. **Timeout Support**: Optional timeout with Task.await

  ## Usage

      # Build a tools map from action modules
      tools = Executor.build_tools_map([MyApp.Calculator, MyApp.Search])

      # Execute by name with explicit tools map
      {:ok, result} = Executor.execute("calculator", %{"a" => "1"}, %{}, tools: tools)

      # With timeout (5 seconds)
      {:ok, result} = Executor.execute("calculator", %{"a" => 1}, %{}, tools: tools, timeout: 5000)

      # Execute directly with a module (no lookup needed)
      {:ok, result} = Executor.execute_module(MyAction, %{a: 1}, %{})

  ## Parameter Normalization

  LLM tool calls return arguments with string keys (from JSON). The executor
  normalizes arguments using the action's schema:

  - Converts string keys to atom keys
  - Parses string numbers to integers/floats based on schema type

  ## Result Formatting

  Results are formatted for LLM consumption:

  - Maps and structs are JSON-encoded
  - Large results are truncated with size indicators
  - Binary data is base64-encoded or described

  ## Error Handling

  All errors are returned as `{:error, error_map}` with structured information:

      {:error, %{
        error: "Error message for LLM",
        tool_name: "calculator",
        type: :execution_error,
        details: %{...}
      }}

  Note: Stacktraces are logged server-side for debugging but are NOT included
  in error responses to prevent information disclosure.

  ## Telemetry

  The executor emits telemetry events for monitoring:

  - `[:jido, :ai, :tool, :execute, :start]` - Execution started
  - `[:jido, :ai, :tool, :execute, :stop]` - Execution completed
  - `[:jido, :ai, :tool, :execute, :exception]` - Execution failed with exception

  Note: Telemetry metadata sanitizes sensitive parameters (api_key, password,
  token, secret, etc.) to prevent credential leakage in logs.
  """

  alias Jido.Action.Tool, as: ActionTool

  require Logger

  @default_timeout 30_000
  @max_result_size 10_000

  @type tools_map :: %{String.t() => module()}
  @type execute_opts :: [timeout: pos_integer(), tools: tools_map()]
  @type execute_result :: {:ok, term()} | {:error, map()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Builds a tools map from action modules.

  Accepts a single module or a list of modules.

  ## Arguments

    * `module_or_modules` - Single Action module or list of Action modules

  ## Returns

    A map of `%{name => module}` for use with `execute/4`.

  ## Examples

      iex> Executor.build_tools_map(MyApp.Calculator)
      %{"calculator" => MyApp.Calculator}

      iex> Executor.build_tools_map([MyApp.Calculator, MyApp.Search])
      %{"calculator" => MyApp.Calculator, "search" => MyApp.Search}
  """
  @spec build_tools_map(module() | [module()]) :: tools_map()
  def build_tools_map(module) when is_atom(module) do
    %{module.name() => module}
  end

  def build_tools_map(modules) when is_list(modules) do
    Map.new(modules, fn module -> {module.name(), module} end)
  end

  @doc """
  Executes a tool by name with the given parameters and context.

  Looks up the tool in the provided tools map, normalizes parameters,
  executes the tool, and returns the formatted result.

  ## Arguments

    * `tool_name` - The name of the tool to execute
    * `params` - Parameters to pass to the tool (may have string keys)
    * `context` - Execution context (passed to Jido.Exec or run/2)
    * `opts` - Optional execution options

  ## Options

    * `:tools` - Map of `%{name => module}` for tool lookup (required)
    * `:timeout` - Timeout in milliseconds (default: 30_000)

  ## Returns

    * `{:ok, result}` - Execution succeeded
    * `{:error, error_map}` - Execution failed

  ## Examples

      iex> tools = Executor.build_tools_map([Calculator])
      iex> Executor.execute("calculator", %{"a" => "1", "b" => "2"}, %{}, tools: tools)
      {:ok, %{result: 3}}

      iex> Executor.execute("unknown_tool", %{}, %{}, tools: %{})
      {:error, %{error: "Tool not found: unknown_tool", type: :not_found}}
  """
  @spec execute(String.t(), map(), map(), execute_opts()) :: execute_result()
  def execute(tool_name, params, context, opts \\ []) when is_binary(tool_name) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tools = Keyword.get(opts, :tools, %{})

    start_telemetry(tool_name, params, context)

    case Map.fetch(tools, tool_name) do
      {:ok, module} ->
        execute_with_timeout(module, tool_name, params, context, timeout)

      :error ->
        error = %{
          error: "Tool not found: #{tool_name}",
          tool_name: tool_name,
          type: :not_found
        }

        stop_telemetry(tool_name, {:error, error}, System.monotonic_time())
        {:error, error}
    end
  end

  @doc """
  Executes a module directly without registry lookup.

  Use this when you already have the Action module reference.

  ## Arguments

    * `module` - The Action module to execute
    * `params` - Parameters to pass to the module
    * `context` - Execution context
    * `opts` - Optional execution options

  ## Options

    * `:timeout` - Timeout in milliseconds (default: 30_000)

  ## Returns

    * `{:ok, result}` - Execution succeeded
    * `{:error, error_map}` - Execution failed
  """
  @spec execute_module(module(), map(), map(), execute_opts()) :: execute_result()
  def execute_module(module, params, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tool_name = module.name()

    start_telemetry(tool_name, params, context)
    execute_with_timeout(module, tool_name, params, context, timeout)
  end

  # ============================================================================
  # Execution
  # ============================================================================

  @spec execute_with_timeout(module(), String.t(), map(), map(), pos_integer()) ::
          execute_result()
  defp execute_with_timeout(module, tool_name, params, context, timeout) do
    start_time = System.monotonic_time()

    task =
      Task.async(fn ->
        execute_internal(module, tool_name, params, context)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        stop_telemetry(tool_name, result, start_time)
        result

      nil ->
        error = %{
          error: "Tool execution timed out after #{timeout}ms",
          tool_name: tool_name,
          type: :timeout,
          timeout_ms: timeout
        }

        exception_telemetry(tool_name, :timeout, start_time)
        {:error, error}
    end
  end

  @spec execute_internal(module(), String.t(), map(), map()) :: execute_result()
  defp execute_internal(module, tool_name, params, context) do
    schema = module.schema()
    normalized_params = normalize_params(params, schema)

    case Jido.Exec.run(module, normalized_params, context) do
      {:ok, output} -> {:ok, format_result(output)}
      {:error, reason} -> {:error, format_error(tool_name, reason)}
    end
  rescue
    e ->
      {:error, format_exception(tool_name, e, __STACKTRACE__)}
  catch
    kind, reason ->
      {:error, format_catch(tool_name, kind, reason)}
  end

  # ============================================================================
  # Parameter Normalization
  # ============================================================================

  @doc """
  Normalizes parameters from LLM format to schema-compliant format.

  Converts string keys to atom keys and parses string values based on
  the schema type definitions.

  ## Arguments

    * `params` - Parameters with potentially string keys and values
    * `schema` - NimbleOptions schema defining expected types

  ## Returns

    A map with normalized parameters.

  ## Examples

      iex> schema = [a: [type: :integer], b: [type: :string]]
      iex> Executor.normalize_params(%{"a" => "42", "b" => "hello"}, schema)
      %{a: 42, b: "hello"}
  """
  @spec normalize_params(map(), keyword() | struct()) :: map()
  def normalize_params(params, schema) when is_map(params) and is_list(schema) do
    params
    |> ActionTool.convert_params_using_schema(schema)
    |> coerce_integers_to_floats(schema)
  end

  def normalize_params(params, %{__struct__: struct_type} = _schema)
      when is_map(params) and struct_type in [Zoi.Types.Map, Zoi.Types.Object] do
    # For Zoi schemas, convert string keys to atoms
    # Zoi will handle the actual type coercion during validation
    atomize_keys(params)
  end

  def normalize_params(params, _schema) when is_map(params), do: params

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), atomize_keys(v)}
      {k, v} when is_atom(k) -> {k, atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  rescue
    ArgumentError ->
      # If atom doesn't exist, try creating it (for dynamic keys)
      Map.new(map, fn
        {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
        {k, v} -> {k, atomize_keys(v)}
      end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other

  defp coerce_integers_to_floats(params, schema) when is_list(schema) do
    float_keys =
      schema
      |> Enum.filter(fn {_key, opts} -> Keyword.get(opts, :type) == :float end)
      |> Enum.map(fn {key, _opts} -> key end)

    Enum.reduce(float_keys, params, fn key, acc ->
      case Map.get(acc, key) do
        val when is_integer(val) -> Map.put(acc, key, val / 1)
        _ -> acc
      end
    end)
  end

  defp coerce_integers_to_floats(params, _schema), do: params

  # ============================================================================
  # Result Formatting
  # ============================================================================

  @doc """
  Formats a tool result for LLM consumption.

  Handles various result types:
  - Maps and structs are JSON-encoded
  - Large results are truncated
  - Binary data is base64-encoded or described
  - Primitives are returned as-is

  ## Arguments

    * `result` - The raw tool result

  ## Returns

    A formatted result suitable for LLM consumption.

  ## Examples

      iex> Executor.format_result(%{answer: 42})
      %{answer: 42}

      iex> Executor.format_result("simple string")
      "simple string"
  """
  @spec format_result(term()) :: term()
  def format_result(result) when is_binary(result) do
    if String.valid?(result) do
      truncate_result(result)
    else
      format_binary(result)
    end
  end

  def format_result(result) when is_map(result) do
    case Jason.encode(result) do
      {:ok, json} ->
        if byte_size(json) > @max_result_size do
          truncate_map_result(result, json)
        else
          result
        end

      {:error, _} ->
        result |> inspect() |> truncate_result()
    end
  end

  def format_result(result) when is_list(result) do
    case Jason.encode(result) do
      {:ok, json} ->
        if byte_size(json) > @max_result_size do
          %{
            truncated: true,
            count: length(result),
            sample: Enum.take(result, 3),
            message: "Result list truncated (#{length(result)} items, #{byte_size(json)} bytes)"
          }
        else
          result
        end

      {:error, _} ->
        result |> inspect() |> truncate_result()
    end
  end

  def format_result(result), do: result

  defp truncate_result(string) when byte_size(string) > @max_result_size do
    truncated = String.slice(string, 0, @max_result_size)
    "#{truncated}... [truncated, #{byte_size(string)} bytes total]"
  end

  defp truncate_result(string), do: string

  defp truncate_map_result(result, json) do
    %{
      truncated: true,
      size_bytes: byte_size(json),
      keys: Map.keys(result) |> Enum.take(10),
      message: "Result map truncated (#{byte_size(json)} bytes)"
    }
  end

  defp format_binary(binary) do
    size = byte_size(binary)
    # Base64 encoding increases size by ~33%, so limit raw bytes to stay under max_result_size
    # For a 10KB limit, we can encode up to ~7.5KB of raw binary data
    max_raw_size = trunc(@max_result_size * 0.75)

    if size <= max_raw_size do
      encoded = Base.encode64(binary)

      %{
        type: :binary,
        encoding: :base64,
        data: encoded,
        size_bytes: size
      }
    else
      %{
        type: :binary,
        encoding: :description,
        message: "Binary data (#{size} bytes) - too large to encode",
        size_bytes: size
      }
    end
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  defp format_error(tool_name, reason) when is_exception(reason) do
    %{
      error: Exception.message(reason),
      tool_name: tool_name,
      type: :execution_error,
      details: %{exception_type: reason.__struct__}
    }
  end

  defp format_error(tool_name, reason) when is_binary(reason) do
    %{
      error: reason,
      tool_name: tool_name,
      type: :execution_error
    }
  end

  defp format_error(tool_name, reason) when is_map(reason) do
    %{
      error: Map.get(reason, :message, inspect(reason)),
      tool_name: tool_name,
      type: :execution_error,
      details: reason
    }
  end

  defp format_error(tool_name, reason) when is_atom(reason) or is_tuple(reason) or is_list(reason) do
    %{
      error: inspect(reason),
      tool_name: tool_name,
      type: :execution_error
    }
  end

  defp format_exception(tool_name, exception, stacktrace) do
    # Log stacktrace server-side for debugging - do NOT include in response
    Logger.error(
      "Tool execution exception",
      tool_name: tool_name,
      exception: Exception.message(exception),
      exception_type: exception.__struct__,
      stacktrace: format_stacktrace_for_logging(stacktrace)
    )

    # Return sanitized error without stacktrace to prevent information disclosure
    %{
      error: Exception.message(exception),
      tool_name: tool_name,
      type: :exception,
      exception_type: exception.__struct__
    }
  end

  defp format_catch(tool_name, kind, reason) do
    %{
      error: "Caught #{kind}: #{inspect(reason)}",
      tool_name: tool_name,
      type: :caught,
      kind: kind
    }
  end

  # Formats stacktrace for server-side logging only - never include in responses
  @doc false
  defp format_stacktrace_for_logging(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Exception.format_stacktrace()
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  # Patterns for sensitive keys that should be redacted in telemetry
  # These match common credential field names but avoid partial matches (e.g. "credentials" container)
  @sensitive_key_patterns [
    ~r/^api_?key$/i,
    ~r/^password$/i,
    ~r/^secret$/i,
    ~r/^token$/i,
    ~r/^auth_?token$/i,
    ~r/^private_?key$/i,
    ~r/^access_?key$/i,
    ~r/^bearer$/i,
    ~r/^api_?secret$/i,
    ~r/^client_?secret$/i,
    ~r/secret_/i,
    ~r/_secret$/i,
    ~r/_key$/i,
    ~r/_token$/i,
    ~r/_password$/i
  ]

  defp start_telemetry(tool_name, params, context) do
    metadata =
      %{
        tool_name: tool_name,
        params: sanitize_params(params),
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        iteration: context[:iteration]
      }
      |> Map.merge(get_trace_metadata())
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    :telemetry.execute(
      [:jido, :ai, :tool, :execute, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  defp get_trace_metadata do
    case Jido.Tracing.Context.get() do
      nil ->
        %{}

      ctx ->
        %{
          jido_trace_id: ctx[:trace_id],
          jido_span_id: ctx[:span_id],
          jido_parent_span_id: ctx[:parent_span_id]
        }
    end
  end

  @doc false
  defp sanitize_params(params) when is_map(params) do
    Map.new(params, fn {key, value} ->
      if sensitive_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, sanitize_value(value)}
      end
    end)
  end

  defp sanitize_params(params), do: params

  defp sanitize_value(value) when is_map(value), do: sanitize_params(value)
  defp sanitize_value(value) when is_list(value), do: Enum.map(value, &sanitize_value/1)
  defp sanitize_value(value), do: value

  defp sensitive_key?(key) when is_atom(key) do
    key |> Atom.to_string() |> sensitive_key?()
  end

  defp sensitive_key?(key) when is_binary(key) do
    Enum.any?(@sensitive_key_patterns, &Regex.match?(&1, key))
  end

  defp sensitive_key?(_key), do: false

  defp stop_telemetry(tool_name, result, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:jido, :ai, :tool, :execute, :stop],
      %{duration: duration},
      %{tool_name: tool_name, result: result}
    )
  end

  defp exception_telemetry(tool_name, reason, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:jido, :ai, :tool, :execute, :exception],
      %{duration: duration},
      %{tool_name: tool_name, reason: reason}
    )
  end
end
