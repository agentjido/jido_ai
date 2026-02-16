defmodule Jido.AI.Executor do
  @moduledoc """
  Action execution boundary for LLM tool calls.

  This module is intentionally narrow:

  1. Resolves tool names to action modules
  2. Normalizes LLM arguments against action schema
  3. Executes via `Jido.Exec`
  4. Normalizes errors into a stable envelope
  5. Emits tool execution telemetry

  Result formatting for tool messages is handled by `Jido.AI.Turn`.
  """

  alias Jido.AI.{Observe, ToolAdapter}
  alias Jido.Action.Error.TimeoutError
  alias Jido.Action.Tool, as: ActionTool

  require Logger

  @default_timeout 30_000

  @type tools_map :: %{String.t() => module()}
  @type execute_opts :: [timeout: pos_integer() | nil, tools: tools_map() | [module()] | module() | nil]
  @type execute_result :: {:ok, term()} | {:error, map()}

  @doc """
  Builds a tools map from action modules.
  """
  @spec build_tools_map(module() | [module()]) :: tools_map()
  def build_tools_map(module) when is_atom(module), do: ToolAdapter.to_action_map(module)
  def build_tools_map(modules) when is_list(modules), do: ToolAdapter.to_action_map(modules)

  @doc """
  Executes a tool by name with the given parameters and context.

  ## Options

    * `:tools` - tool registry as map/list/module
    * `:timeout` - timeout in milliseconds (default: 30_000)
  """
  @spec execute(String.t(), map(), map(), execute_opts()) :: execute_result()
  def execute(tool_name, params, context, opts \\ []) when is_binary(tool_name) do
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tools = opts |> Keyword.get(:tools, %{}) |> ToolAdapter.to_action_map()
    start_time = System.monotonic_time()

    start_telemetry(tool_name, params, context)

    result =
      case Map.fetch(tools, tool_name) do
        {:ok, module} ->
          execute_internal(module, tool_name, params, context, timeout)

        :error ->
          {:error,
           %{
             error: "Tool not found: #{tool_name}",
             tool_name: tool_name,
             type: :not_found
           }}
      end

    finalize_telemetry(tool_name, result, start_time, context)
    result
  end

  @doc """
  Executes a module directly without registry lookup.
  """
  @spec execute_module(module(), map(), map(), execute_opts()) :: execute_result()
  def execute_module(module, params, context, opts \\ []) do
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tool_name = module.name()
    start_time = System.monotonic_time()

    start_telemetry(tool_name, params, context)
    result = execute_internal(module, tool_name, params, context, timeout)
    finalize_telemetry(tool_name, result, start_time, context)

    result
  end

  # ============================================================================
  # Execution
  # ============================================================================

  @spec execute_internal(module(), String.t(), map(), map(), pos_integer() | nil) :: execute_result()
  defp execute_internal(module, tool_name, params, context, timeout) do
    schema = module.schema()
    normalized_params = normalize_params(params, schema)

    case Jido.Exec.run(module, normalized_params, context, timeout_opts(timeout)) do
      {:ok, output} -> {:ok, output}
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
  """
  @spec normalize_params(map(), keyword() | struct()) :: map()
  def normalize_params(params, schema) when is_map(params) do
    ActionTool.convert_params_using_schema(params, schema)
  end

  # ============================================================================
  # Legacy Compatibility
  # ============================================================================

  @deprecated "Use Jido.AI.Turn.format_tool_result_content/1 for tool message formatting."
  @doc """
  Returns the result unchanged.

  Kept for backward compatibility. Formatting for tool messages lives in `Jido.AI.Turn`.
  """
  @spec format_result(term()) :: term()
  def format_result(result), do: result

  # ============================================================================
  # Error Formatting
  # ============================================================================

  defp format_error(tool_name, %TimeoutError{} = reason) do
    timeout_ms = reason.timeout || timeout_from_details(reason.details)

    %{
      error: Exception.message(reason),
      tool_name: tool_name,
      type: :timeout,
      timeout_ms: timeout_ms,
      details: reason.details
    }
  end

  defp format_error(tool_name, reason) when is_exception(reason) do
    %{
      error: Exception.message(reason),
      tool_name: tool_name,
      type: :execution_error,
      details: %{exception_type: reason.__struct__}
    }
  end

  defp format_error(tool_name, reason) do
    %{
      error: inspect(reason),
      tool_name: tool_name,
      type: :execution_error,
      details: if(is_map(reason), do: reason, else: nil)
    }
  end

  defp format_exception(tool_name, exception, stacktrace) do
    Logger.error("Tool execution exception",
      tool_name: tool_name,
      exception_message: Exception.message(exception),
      exception_type: exception.__struct__,
      stacktrace: format_stacktrace_for_logging(stacktrace)
    )

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

  defp timeout_from_details(%{} = details), do: Map.get(details, :timeout) || Map.get(details, "timeout")
  defp timeout_from_details(_), do: nil

  @doc false
  defp format_stacktrace_for_logging(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Exception.format_stacktrace()
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp finalize_telemetry(tool_name, {:error, %{type: :timeout}}, start_time, context) do
    exception_telemetry(tool_name, :timeout, start_time, context)
  end

  defp finalize_telemetry(tool_name, result, start_time, context) do
    stop_telemetry(tool_name, result, start_time, context)
  end

  defp start_telemetry(tool_name, params, context) do
    obs_cfg = context[:observability] || %{}

    metadata =
      %{
        tool_name: tool_name,
        params: Observe.sanitize_sensitive(params),
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:start),
      %{system_time: System.system_time()},
      metadata
    )
  end

  defp stop_telemetry(tool_name, result, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        result: result,
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:stop),
      %{duration: duration},
      metadata
    )
  end

  defp exception_telemetry(tool_name, reason, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        reason: reason,
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:exception),
      %{duration: duration},
      metadata
    )
  end

  defp timeout_opts(timeout) when is_integer(timeout) and timeout > 0, do: [timeout: timeout]
  defp timeout_opts(_), do: []

  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}
end
