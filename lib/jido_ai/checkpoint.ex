defmodule Jido.AI.Checkpoint do
  @moduledoc """
  Checkpoint sanitization and rehydration for `Jido.AI.Agent` state.

  Durable checkpoints outlive the VM that wrote them. Anything process-local —
  pids, ports, references — and any anonymous function is therefore unsafe to
  persist: `:erlang.binary_to_term/2` with `[:safe]` refuses to decode both, so
  a checkpoint containing them cannot be read back at all once the writing node
  is gone.

  ## Why `[:safe]` matters

  Storage adapters decode untrusted bytes with `[:safe]` to avoid unbounded atom
  creation. That option rejects:

  - **Pids/ports/refs** whose node atom does not already exist in the decoding
    VM. A checkpoint written by `app@host.example.com` becomes undecodable after
    a switch to short names, surfacing as `{:error, :invalid_term}`.
  - **Anonymous functions**, unconditionally — even when the defining module is
    loaded and no new atoms are involved.

  Both classes are runtime handles that are meaningless after a thaw anyway: the
  process they point at is dead, and the function is rebuilt from compiled code.

  ## What is stripped

  | Path | Reason | On restore |
  | --- | --- | --- |
  | `state.requests[id].stream_to` | Request stream sink (`{:pid, pid}`) | Dropped; active requests are flagged `stream_interrupted: true` |
  | `state.__strategy__.react_worker_pid` | ReAct worker process | Reset to `nil` / `:missing` |
  | `state.__strategy__.pending_input_server` | Steering queue process | Reset to `nil` |
  | `state.__strategy__.pending_worker_start` | Queued worker payload embedding a state snapshot | Reset to `nil` |

  `state.__strategy__.config.reqllm_tools` stays in the payload. Its callback is
  the durable MFA placeholder `{ReqLLM.Tool, :new}`, so an older reader still
  receives the field and a new VM can decode it with `[:safe]`.

  The per-instance `Task.Supervisor` is dropped by
  `Jido.AI.Plugins.TaskSupervisor.on_checkpoint/2` and re-mounted by `new/1`
  during restore.

  ## Restore contract for interrupted streamed requests

  A stream sink is process-local, so it can never survive a thaw. A request that
  was still in flight when the checkpoint was written is restored with:

  - no `:stream_to` — nothing will ever be delivered to the original consumer,
  - `stream_interrupted: true` — a durable marker that the run was cut short,
  - `status: :failed` and `error: :stream_interrupted`.

  The parent strategy also restores to an idle state with no active request.
  Callers can re-issue the query, and `Jido.AI.Request.await/2` on the old handle
  returns `{:error, :stream_interrupted}` immediately. Use
  `interrupted_request?/1` to detect these requests in state.

  ## Residual handles

  `runtime_handles/1` walks a term and reports every remaining pid, port,
  reference, and anonymous function with the path it was found at. `checkpoint/2`
  logs a warning listing them, so state that a future change starts persisting is
  reported instead of silently producing unreadable checkpoints.
  """

  require Logger

  alias Jido.AI.Request
  alias Jido.AI.ToolAdapter

  @strategy_key :__strategy__

  @typedoc "Location of a runtime handle inside a term, outermost segment first."
  @type handle_path :: [term()]

  @typedoc "A non-serializable value found in a term."
  @type handle :: {handle_path(), :pid | :port | :reference | :function}

  # Strategy fields holding process handles, with the value each is reset to.
  @strategy_handle_resets %{
    react_worker_pid: nil,
    react_worker_status: :missing,
    pending_worker_start: nil,
    pending_input_server: nil
  }

  # An in-flight ReAct run cannot continue after thaw. Reset its run-local
  # logical state while preserving durable context, request traces, and config.
  @interrupted_run_resets %{
    status: :idle,
    iteration: 0,
    run_context: nil,
    pending_tool_calls: [],
    tool_results: [],
    final_answer: nil,
    result: nil,
    current_llm_call_id: nil,
    termination_reason: nil,
    run_tool_context: %{},
    run_req_http_options: [],
    run_llm_opts: [],
    active_request_id: nil,
    pending_input_server: nil,
    last_pending_input_control: nil,
    cancel_reason: nil,
    usage: %{},
    started_at: nil,
    streaming_text: "",
    streaming_thinking: "",
    thinking_trace: [],
    checkpoint_token: nil,
    react_worker_pid: nil,
    react_worker_status: :missing,
    pending_worker_start: nil
  }

  @doc """
  Removes every process-local runtime handle from agent state.

  Operates on the checkpoint copy of the state; the live agent keeps its
  handles.

  ## Examples

      iex> state = %{requests: %{"r1" => %{status: :pending, stream_to: {:pid, self()}}}}
      iex> Jido.AI.Checkpoint.sanitize_state(state)
      %{requests: %{"r1" => %{status: :failed, error: :stream_interrupted, stream_interrupted: true}}}
  """
  @spec sanitize_state(map()) :: map()
  def sanitize_state(state) when is_map(state) do
    state
    |> Request.sanitize_requests(:checkpoint)
    |> update_strategy(&sanitize_strategy/1)
  end

  def sanitize_state(state), do: state

  @doc """
  Rebuilds derived runtime values dropped by `sanitize_state/1`.

  Called on the restore path. Also scrubs stream sinks from legacy checkpoints
  written before sanitization existed, so a decodable old payload still restores
  without a stale pid.
  """
  @spec rehydrate_state(map()) :: map()
  def rehydrate_state(state) when is_map(state) do
    state
    |> Request.sanitize_requests(:restore)
    |> update_strategy(&rehydrate_strategy/1)
  end

  def rehydrate_state(state), do: state

  @doc """
  Returns true when a restored request lost its stream sink mid-flight.

  ## Examples

      iex> Jido.AI.Checkpoint.interrupted_request?(%{stream_interrupted: true})
      true

      iex> Jido.AI.Checkpoint.interrupted_request?(%{status: :completed})
      false
  """
  @spec interrupted_request?(map() | nil) :: boolean()
  def interrupted_request?(%{stream_interrupted: true}), do: true
  def interrupted_request?(_request), do: false

  @doc """
  Walks `term` and returns every pid, port, reference, and anonymous function.

  Paths read outermost segment first. Tuple elements appear as `{:elem, index}`,
  list elements as `{:at, index}`, and struct contents are prefixed with the
  struct module.

  External function captures (`&Mod.fun/1`) are not reported: they encode as a
  module/function/arity triple that `[:safe]` accepts.

  ## Examples

      iex> Jido.AI.Checkpoint.runtime_handles(%{a: %{b: [self()]}})
      [{[:a, :b, {:at, 0}], :pid}]

      iex> Jido.AI.Checkpoint.runtime_handles(%{ok: [1, "two", :three]})
      []
  """
  @spec runtime_handles(term()) :: [handle()]
  def runtime_handles(term), do: term |> collect_handles([], []) |> Enum.reverse()

  @doc """
  Formats `runtime_handles/1` output as a human-readable list.
  """
  @spec format_handles([handle()]) :: String.t()
  def format_handles(handles) when is_list(handles) do
    Enum.map_join(handles, ", ", fn {path, kind} -> "#{kind} at #{format_path(path)}" end)
  end

  @doc false
  @spec warn_on_residual_handles(module(), map()) :: :ok
  def warn_on_residual_handles(agent_module, payload) do
    case runtime_handles(payload) do
      [] ->
        :ok

      handles ->
        Logger.warning(
          "#{inspect(agent_module)} checkpoint retains non-serializable runtime handles; " <>
            "the payload will not decode with binary_to_term/2 [:safe] on another node: " <>
            format_handles(handles)
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy state
  # ---------------------------------------------------------------------------

  defp update_strategy(state, fun) do
    case Map.get(state, @strategy_key) do
      strategy when is_map(strategy) -> Map.put(state, @strategy_key, fun.(strategy))
      _absent -> state
    end
  end

  defp sanitize_strategy(strategy) do
    strategy
    |> reset_interrupted_run()
    |> reset_react_handles()
    |> update_strategy_config(&restore_reqllm_tools/1)
  end

  defp rehydrate_strategy(strategy) do
    strategy
    |> reset_interrupted_run()
    |> reset_react_handles()
    |> update_strategy_config(&restore_reqllm_tools/1)
  end

  defp reset_interrupted_run(strategy) do
    if react_run_active?(strategy) do
      Map.merge(strategy, @interrupted_run_resets)
    else
      strategy
    end
  end

  defp react_run_active?(strategy) do
    react_strategy_state?(strategy) and
      (is_binary(Map.get(strategy, :active_request_id)) or
         Map.get(strategy, :status) in [:awaiting_llm, :awaiting_tool] or
         Map.get(strategy, :react_worker_status) in [:starting, :running])
  end

  defp reset_react_handles(strategy) do
    if react_strategy_state?(strategy), do: Map.merge(strategy, @strategy_handle_resets), else: strategy
  end

  defp react_strategy_state?(strategy) do
    Map.has_key?(strategy, :react_worker_pid) or Map.has_key?(strategy, :react_worker_status)
  end

  defp update_strategy_config(strategy, fun) do
    case Map.get(strategy, :config) do
      config when is_map(config) -> Map.put(strategy, :config, fun.(config))
      _absent -> strategy
    end
  end

  # `reqllm_tools` is a pure projection of `config.tools`. Rebuild it to replace
  # callbacks created by older releases and to restore payloads written by an
  # earlier version of this checkpoint sanitizer that dropped the field.
  defp restore_reqllm_tools(%{tools: tools} = config) when is_list(tools) do
    Map.put(config, :reqllm_tools, ToolAdapter.from_actions(tools))
  end

  defp restore_reqllm_tools(config), do: config

  # ---------------------------------------------------------------------------
  # Handle scanning
  # ---------------------------------------------------------------------------

  defp collect_handles(term, path, acc) when is_pid(term), do: [{Enum.reverse(path), :pid} | acc]
  defp collect_handles(term, path, acc) when is_port(term), do: [{Enum.reverse(path), :port} | acc]

  defp collect_handles(term, path, acc) when is_reference(term) do
    [{Enum.reverse(path), :reference} | acc]
  end

  defp collect_handles(term, path, acc) when is_function(term) do
    if external_capture?(term), do: acc, else: [{Enum.reverse(path), :function} | acc]
  end

  defp collect_handles(%module{} = term, path, acc) do
    term |> Map.from_struct() |> collect_handles([module | path], acc)
  end

  defp collect_handles(term, path, acc) when is_map(term) do
    Enum.reduce(term, acc, fn {key, value}, inner ->
      inner = collect_handles(key, [{:key, key} | path], inner)
      collect_handles(value, [key | path], inner)
    end)
  end

  defp collect_handles(term, path, acc) when is_list(term) do
    collect_list_handles(term, 0, path, acc)
  end

  defp collect_handles(term, path, acc) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, index}, inner -> collect_handles(value, [{:elem, index} | path], inner) end)
  end

  defp collect_handles(_term, _path, acc), do: acc

  defp collect_list_handles([], _index, _path, acc), do: acc

  defp collect_list_handles([head | tail], index, path, acc) do
    acc = collect_handles(head, [{:at, index} | path], acc)
    collect_list_handles(tail, index + 1, path, acc)
  end

  defp collect_list_handles(tail, index, path, acc) do
    collect_handles(tail, [{:tail, index} | path], acc)
  end

  defp external_capture?(fun) do
    Function.info(fun, :type) == {:type, :external}
  end

  defp format_path([]), do: "<root>"

  defp format_path(path) do
    Enum.map_join(path, ".", fn
      {:at, index} -> "[#{index}]"
      {:tail, index} -> "[tail@#{index}]"
      {:key, key} -> "[key #{inspect(key)}]"
      {:elem, index} -> "{#{index}}"
      segment when is_binary(segment) -> segment
      segment -> inspect(segment)
    end)
  end
end
