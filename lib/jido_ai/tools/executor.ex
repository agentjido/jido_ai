defmodule Jido.AI.Tools.Executor do
  @moduledoc """
  Executes tools through core Exec and normalizes their results.

  Direct execution applies the caller's effect policy. Profile execution uses
  execute_target/5 inside its bounded attempt, then applies Profile controls,
  interception, and effect policy before committing any proposed state.
  """
  alias Jido.AI.{Effects, Error, Observe, ToolAdapter, Turn}
  require Logger
  @default_timeout 30_000
  @type execute_opts :: [
          timeout: pos_integer() | nil,
          tools: map() | [module()] | module() | nil,
          telemetry_metadata: map()
        ]
  @type execute_result :: {:ok, term(), [term()]} | {:error, term(), [term()]}
  @type run_opts :: [timeout: pos_integer() | nil, tools: map() | [module()] | module() | nil]

  @doc false
  def execute_target(target, arguments, context, options, call) do
    Jido.Exec.run(target, arguments, context, options)
    |> Jido.AI.ToolResult.normalize(call)
  end

  @doc """
  Executes a tool by name using a tools map and returns raw action output.
  """
  @spec execute(String.t(), map(), map(), execute_opts()) :: execute_result()
  def execute(tool_name, params, context, opts \\ []) when is_binary(tool_name) do
    opts = Keyword.validate!(opts, [:timeout, :tools, :telemetry_metadata])
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    exec_opts = opts |> Keyword.delete(:timeout) |> Keyword.delete(:telemetry_metadata)
    tools = opts |> Keyword.get(:tools, %{}) |> ToolAdapter.to_action_map()
    telemetry_context = telemetry_context(context, opts)
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, telemetry_context)

    result =
      case Map.fetch(tools, tool_name) do
        {:ok, module} ->
          execute_internal(module, tool_name, params, context, timeout, exec_opts)

        :error ->
          {:error,
           Error.error_envelope(
             :not_found,
             "Tool not found: #{tool_name}",
             %{tool_name: tool_name},
             false
           ), []}
      end

    finalize_execute_telemetry(tool_name, result, start_time, telemetry_context)
    result
  end

  @doc """
  Executes an action module directly without registry lookup.
  """
  @spec execute_module(module(), map(), map(), execute_opts()) :: execute_result()
  def execute_module(module, params, context, opts \\ []) do
    opts = Keyword.validate!(opts, [:timeout, :tools, :telemetry_metadata])
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    exec_opts = opts |> Keyword.delete(:timeout) |> Keyword.delete(:telemetry_metadata)
    telemetry_context = telemetry_context(context, opts)
    tool_name = module.name()
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, telemetry_context)
    result = execute_internal(module, tool_name, params, context, timeout, exec_opts)
    finalize_execute_telemetry(tool_name, result, start_time, telemetry_context)

    result
  end

  @doc """
  Executes all requested tools for the turn and returns the updated turn.
  """
  @spec run_tools(Turn.t(), map(), run_opts()) :: {:ok, Turn.t()} | {:error, term()}
  def run_tools(turn, context, opts \\ [])

  def run_tools(%Turn{type: :tool_calls} = turn, context, opts) do
    with {:ok, tool_results} <- run_tool_calls(turn.tool_calls, context, opts) do
      {:ok, Turn.with_tool_results(turn, tool_results)}
    end
  end

  def run_tools(%Turn{tool_calls: tool_calls} = turn, context, opts)
      when is_list(tool_calls) and tool_calls != [] do
    with {:ok, tool_results} <- run_tool_calls(tool_calls, context, opts) do
      {:ok, Turn.with_tool_results(turn, tool_results)}
    end
  end

  def run_tools(%Turn{} = turn, _context, _opts), do: {:ok, turn}

  @doc """
  Executes normalized tool calls and returns normalized tool results.
  """
  @spec run_tool_calls([term()], map(), run_opts()) :: {:ok, [Turn.tool_result()]}
  def run_tool_calls(tool_calls, context, opts \\ []) when is_list(tool_calls) do
    tools = resolve_tools(context, opts)
    timeout = normalize_timeout(Keyword.get(opts, :timeout))

    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        run_single_tool(tool_call, context, tools, timeout)
      end)

    {:ok, tool_results}
  end

  defp execute_internal(module, tool_name, params, context, timeout, exec_opts) do
    schema = module.schema()
    normalized_params = Jido.AI.SchemaInput.normalize_tool(schema, params)

    # Registry and AI observation options do not belong to core Exec.
    run_opts = timeout_opts(timeout) ++ Keyword.delete(exec_opts, :tools)

    result =
      execute_target(module, normalized_params, context, run_opts, %{
        name: tool_name,
        id: context[:tool_call_id] || context[:call_id]
      })

    apply_effect_policy(result, context)
  rescue
    e ->
      {:error, format_exception(tool_name, e, __STACKTRACE__), []}
  catch
    kind, reason ->
      {:error, format_catch(tool_name, kind, reason), []}
  end

  defp format_exception(tool_name, exception, stacktrace) do
    Logger.error("Tool execution exception",
      tool_name: tool_name,
      exception_message: Exception.message(exception),
      exception_type: exception.__struct__,
      stacktrace: format_stacktrace_for_logging(stacktrace)
    )

    message = Exception.message(exception)

    Error.error_envelope(
      :exception,
      message,
      %{tool_name: tool_name, exception_type: exception.__struct__},
      false
    )
  end

  defp format_catch(tool_name, kind, reason) do
    message = "Caught #{kind}: #{inspect(reason)}"

    Error.error_envelope(
      :caught,
      message,
      %{tool_name: tool_name, kind: kind, reason: inspect(reason)},
      false
    )
  end

  defp finalize_execute_telemetry(
         tool_name,
         {:error, %{type: :timeout}, _effects},
         start_time,
         context
       ) do
    exception_execute_telemetry(tool_name, :timeout, start_time, context)
  end

  defp finalize_execute_telemetry(tool_name, result, start_time, context) do
    stop_execute_telemetry(tool_name, result, start_time, context)
  end

  defp start_execute_telemetry(tool_name, params, context) do
    obs_cfg = context[:observability] || %{}
    tool_call_id = context[:tool_call_id] || context[:call_id]

    metadata =
      %{
        tool_name: tool_name,
        params: Observe.sanitize_sensitive(params),
        tool_call_id: tool_call_id,
        call_id: context[:call_id],
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
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

  defp stop_execute_telemetry(tool_name, result, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration_native = System.monotonic_time() - start_time
    tool_call_id = context[:tool_call_id] || context[:call_id]

    metadata =
      %{
        tool_name: tool_name,
        result: result,
        tool_result: extract_tool_result(result),
        tool_call_id: tool_call_id,
        call_id: context[:call_id],
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:stop),
      duration_measurements(duration_native),
      metadata
    )
  end

  defp exception_execute_telemetry(tool_name, reason, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration_native = System.monotonic_time() - start_time
    tool_call_id = context[:tool_call_id] || context[:call_id]

    metadata =
      %{
        tool_name: tool_name,
        reason: reason,
        tool_call_id: tool_call_id,
        call_id: context[:call_id],
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:exception),
      duration_measurements(duration_native),
      metadata
    )
  end

  defp duration_measurements(duration_native) do
    %{
      duration_ms: System.convert_time_unit(duration_native, :native, :millisecond),
      duration: duration_native
    }
  end

  defp timeout_opts(timeout) when is_integer(timeout) and timeout > 0, do: [timeout: timeout]
  defp timeout_opts(_), do: []

  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

  defp telemetry_context(context, opts) do
    telemetry_metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> normalize_context()

    Map.merge(context, telemetry_metadata)
  end

  defp tool_call_telemetry_metadata(""), do: nil
  defp tool_call_telemetry_metadata(call_id), do: %{call_id: call_id, tool_call_id: call_id}

  defp run_single_tool(tool_call, context, tools, timeout) do
    %{id: call_id, name: tool_name, arguments: arguments} =
      Turn.normalize_tool_call(if(is_map(tool_call), do: tool_call, else: %{}))

    exec_opts =
      [tools: tools]
      |> maybe_add_timeout(timeout)
      |> maybe_put_keyword(:telemetry_metadata, tool_call_telemetry_metadata(call_id))

    raw_result =
      case tool_name do
        "" ->
          {:error, Error.error_envelope(:validation, "Missing tool name"), []}

        _ ->
          execute(tool_name, arguments, context, exec_opts)
      end

    %{
      id: call_id,
      name: tool_name,
      content: Jido.AI.ToolResult.content(raw_result),
      raw_result: raw_result
    }
  end

  defp resolve_tools(context, opts) do
    context = normalize_context(context)

    tools_input =
      Keyword.get(opts, :tools) ||
        get_field(context, :tools) ||
        get_in(context, [:tool_calling, :tools]) ||
        get_in(context, [:state, :tool_calling, :tools]) ||
        get_in(context, [:agent, :state, :tool_calling, :tools]) ||
        get_in(context, [:plugin_state, :tool_calling, :tools])

    ToolAdapter.to_action_map(tools_input)
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(_), do: nil

  defp maybe_add_timeout(opts, nil), do: opts
  defp maybe_add_timeout(opts, timeout), do: Keyword.put(opts, :timeout, timeout)

  defp format_stacktrace_for_logging(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Exception.format_stacktrace()
  end

  defp apply_effect_policy(result, context) do
    policy = Effects.policy_from_context(context, Effects.default_policy())
    {filtered_result, stats} = Effects.filter_result(result, policy)

    if stats.dropped_count > 0 do
      Logger.debug("Dropped disallowed tool effects count=#{stats.dropped_count} status=#{elem(filtered_result, 0)}")
    end

    filtered_result
  end

  # Extract a compact tool result payload for telemetry (bypasses :result summary sanitization
  # so downstream bridges get the actual payload data rather than a type/size summary).
  defp extract_tool_result({:ok, result, _effects}), do: result
  defp extract_tool_result({:error, _reason, _effects}), do: nil

  defp get_field(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp maybe_put_keyword(keyword, _key, nil), do: keyword
  defp maybe_put_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)
end
