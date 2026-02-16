defmodule Jido.AI.ReAct.Machine do
  @moduledoc """
  Pure state machine for the ReAct (Reason-Act) pattern.

  This module implements the core state transitions for a ReAct agent without
  any side effects. It uses Fsmx for state machine management and returns
  directives that describe what external effects should be performed.

  ## States

  - `:idle` - Initial state, waiting for a user query
  - `:awaiting_llm` - Waiting for LLM response
  - `:awaiting_tool` - Waiting for tool execution results
  - `:completed` - Final state, conversation complete
  - `:error` - Error state

  ## Thread-based Conversation History

  The machine uses `Jido.AI.Thread` to accumulate conversation history. The thread
  is a simple append-only list of messages that gets projected to ReqLLM format
  when making LLM calls.

  ## Usage

  The machine is used by the ReAct strategy:

      machine = Machine.new(config)
      {machine, directives} = Machine.update(machine, {:start, query, call_id})

  All state transitions are pure - side effects are described in directives.

  ## Status Type Boundary

  **Internal (Machine struct):** Status is stored as strings (`"idle"`, `"completed"`)
  due to Fsmx library requirements.

  **External (Strategy state, Snapshots):** Status is converted to atoms (`:idle`,
  `:completed`) via `to_map/1` before storage in agent state.

  Never compare `machine.status` directly with atoms - use `Machine.to_map/1` first.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["awaiting_llm"],
      "awaiting_llm" => ["awaiting_tool", "completed", "error"],
      "awaiting_tool" => ["awaiting_llm", "completed", "error"],
      "completed" => ["awaiting_llm"],
      "error" => ["awaiting_llm"]
    }

  alias Jido.AI.{Observe, Thread, Turn}

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :awaiting_llm | :awaiting_tool | :completed | :error

  @type termination_reason :: :final_answer | :max_iterations | :error | :cancelled | nil

  @type pending_tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          result: term() | nil
        }

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer(),
          optional(:cache_creation_input_tokens) => non_neg_integer(),
          optional(:cache_read_input_tokens) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          status: internal_status(),
          iteration: non_neg_integer(),
          thread: Thread.t() | nil,
          pending_tool_calls: [pending_tool_call()],
          result: term(),
          active_request_id: String.t() | nil,
          current_llm_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          cancel_reason: atom() | nil,
          streaming_text: String.t(),
          streaming_thinking: String.t(),
          thinking_trace: [%{call_id: String.t(), iteration: non_neg_integer(), thinking: String.t()}],
          usage: usage(),
          started_at: integer() | nil
        }

  defstruct status: "idle",
            iteration: 0,
            thread: nil,
            pending_tool_calls: [],
            result: nil,
            active_request_id: nil,
            current_llm_call_id: nil,
            termination_reason: nil,
            cancel_reason: nil,
            streaming_text: "",
            streaming_thinking: "",
            thinking_trace: [],
            usage: %{},
            started_at: nil

  @type msg ::
          {:start, query :: String.t(), request_id :: String.t()}
          | {:llm_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}
          | {:tool_result, call_id :: String.t(), result :: term()}
          | {:cancel, request_id :: String.t() | nil, reason :: atom()}

  @type directive ::
          {:call_llm_stream, id :: String.t(), context :: list()}
          | {:exec_tool, id :: String.t(), tool_name :: String.t(), arguments :: map()}
          | {:request_error, request_id :: String.t(), reason :: atom(), message :: String.t()}

  @doc """
  Creates a new machine in the idle state.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Updates the machine state based on a message.

  Returns the updated machine and a list of directives describing
  external effects to be performed.

  ## Messages

  - `{:start, query, call_id}` - Start a new conversation
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunk
  - `{:tool_result, call_id, result}` - Handle tool execution result

  ## Directives

  - `{:call_llm_stream, id, context}` - Request LLM call
  - `{:exec_tool, id, tool_name, arguments}` - Request tool execution
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, query, request_id}, env) do
    do_start_fresh(machine, query, request_id, env)
  end

  def update(%__MODULE__{status: status} = machine, {:start, query, request_id}, env)
      when status in ["completed", "error"] do
    # Continue conversation - append new user message to existing history
    do_start_continue(machine, query, request_id, env)
  end

  # Issue #3 fix: Explicitly reject start requests when busy instead of silently dropping
  def update(%__MODULE__{status: status} = machine, {:start, _query, request_id}, env)
      when status in ["awaiting_llm", "awaiting_tool"] do
    case Map.get(env, :request_policy, :reject) do
      :reject ->
        emit_request_event(
          :rejected,
          %{duration_ms: 0},
          %{
            request_id: request_id,
            run_id: request_id,
            termination_reason: :busy,
            error_type: :busy
          },
          env
        )

        {machine, [{:request_error, request_id, :busy, "Agent is busy (status: #{status})"}]}

      _ ->
        {machine, [{:request_error, request_id, :busy, "Agent is busy (status: #{status})"}]}
    end
  end

  def update(%__MODULE__{status: "awaiting_llm"} = machine, {:llm_result, call_id, result}, env) do
    if call_id == machine.current_llm_call_id do
      handle_llm_response(machine, result, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: "awaiting_llm"} = machine, {:llm_partial, call_id, delta, chunk_type}, _env) do
    if call_id == machine.current_llm_call_id do
      machine =
        case chunk_type do
          :content ->
            Map.update!(machine, :streaming_text, &(&1 <> delta))

          :thinking ->
            Map.update!(machine, :streaming_thinking, &(&1 <> delta))

          _ ->
            machine
        end

      {machine, []}
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: "awaiting_tool"} = machine, {:tool_result, call_id, result}, env) do
    max_iterations = Map.get(env, :max_iterations, 10)
    {machine, all_complete?} = record_tool_result(machine, call_id, result)

    if all_complete? do
      machine
      |> append_all_tool_results()
      |> inc_iteration()
      |> handle_iteration_check(max_iterations, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: status} = machine, {:cancel, request_id, reason}, env)
      when status in ["awaiting_llm", "awaiting_tool"] do
    if is_nil(request_id) or request_id == machine.active_request_id do
      duration_ms = calculate_duration(machine)

      emit_request_event(
        :cancelled,
        %{duration_ms: duration_ms},
        %{
          request_id: machine.active_request_id,
          run_id: machine.active_request_id,
          termination_reason: :cancelled,
          error_type: reason
        },
        env
      )

      with_transition(machine, "error", fn m ->
        m =
          m
          |> Map.put(:termination_reason, :cancelled)
          |> Map.put(:cancel_reason, reason)
          |> Map.put(:result, "Request cancelled (reason: #{inspect(reason)})")

        {m, []}
      end)
    else
      {machine, []}
    end
  end

  def update(machine, _msg, _env) do
    {machine, []}
  end

  # Fresh start - create new thread with system prompt
  defp do_start_fresh(machine, query, request_id, env) do
    system_prompt = Map.fetch!(env, :system_prompt)

    thread =
      Thread.new(system_prompt: system_prompt)
      |> Thread.append_user(query)

    do_start_with_thread(machine, thread, request_id, env)
  end

  # Continue existing conversation - append user message to existing thread
  defp do_start_continue(machine, query, request_id, env) do
    thread = Thread.append_user(machine.thread, query)
    do_start_with_thread(machine, thread, request_id, env)
  end

  defp do_start_with_thread(machine, thread, request_id, env) do
    started_at = System.monotonic_time(:millisecond)

    # Get the last entry (user message) for telemetry
    last_entry = Thread.last_entry(thread)
    query_length = if last_entry, do: String.length(last_entry.content || ""), else: 0

    # Emit start telemetry
    emit_telemetry(
      :start,
      %{system_time: System.system_time()},
      %{
        call_id: request_id,
        query_length: query_length,
        thread_id: thread.id
      },
      env
    )

    emit_request_event(
      :start,
      %{duration_ms: 0},
      %{
        request_id: request_id,
        run_id: request_id,
        termination_reason: nil,
        error_type: nil
      },
      env
    )

    with_transition(machine, "awaiting_llm", fn machine ->
      machine =
        machine
        |> Map.put(:iteration, 1)
        |> Map.put(:thread, thread)
        |> Map.put(:pending_tool_calls, [])
        |> Map.put(:result, nil)
        |> Map.put(:active_request_id, request_id)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:cancel_reason, nil)
        |> Map.put(:current_llm_call_id, request_id)
        |> Map.put(:streaming_text, "")
        |> Map.put(:streaming_thinking, "")
        |> Map.put(:thinking_trace, [])
        |> Map.put(:usage, %{})
        |> Map.put(:started_at, started_at)

      # Project thread to messages for LLM call
      messages = Thread.to_messages(thread)
      {machine, [{:call_llm_stream, request_id, messages}]}
    end)
  end

  defp handle_iteration_check(machine, max_iterations, env) when machine.iteration > max_iterations do
    duration_ms = calculate_duration(machine)

    # Emit complete telemetry for max iterations
    emit_telemetry(
      :complete,
      %{duration: duration_ms},
      %{
        iteration: machine.iteration,
        termination_reason: :max_iterations,
        usage: machine.usage,
        thread_id: thread_id(machine)
      },
      env
    )

    emit_request_event(
      :complete,
      %{duration_ms: duration_ms},
      %{
        request_id: machine.active_request_id,
        run_id: machine.active_request_id,
        termination_reason: :max_iterations,
        error_type: nil
      },
      env
    )

    with_transition(machine, "completed", fn m ->
      m =
        Map.merge(m, %{
          termination_reason: :max_iterations,
          result: "Maximum iterations reached without a final answer."
        })

      {m, []}
    end)
  end

  defp handle_iteration_check(machine, _max_iterations, env) do
    new_call_id = generate_call_id(machine.active_request_id)

    machine = capture_thinking_to_trace(machine)

    emit_telemetry(
      :iteration,
      %{system_time: System.system_time()},
      %{
        iteration: machine.iteration,
        call_id: new_call_id,
        thread_id: thread_id(machine)
      },
      env
    )

    with_transition(machine, "awaiting_llm", fn m ->
      m = Map.merge(m, %{current_llm_call_id: new_call_id, streaming_text: "", streaming_thinking: ""})
      messages = Thread.to_messages(m.thread)
      {m, [{:call_llm_stream, new_call_id, messages}]}
    end)
  end

  @doc """
  Converts the machine state to a map suitable for strategy state storage.

  The thread is converted to a plain conversation list for storage compatibility.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
    |> convert_thread_for_storage()
  end

  # Convert thread to conversation list for backward compatibility with strategy state
  defp convert_thread_for_storage(map) do
    case map[:thread] do
      nil ->
        map
        |> Map.delete(:thread)
        |> Map.put(:conversation, [])

      %Thread{} = thread ->
        # Store as conversation list (without system prompt, since that's stored separately)
        # Also store the thread struct for full fidelity
        map
        |> Map.put(:conversation, Thread.to_messages(thread))
        |> Map.put(:thread, thread)

      # Already a list (shouldn't happen, but handle it)
      list when is_list(list) ->
        map
        |> Map.delete(:thread)
        |> Map.put(:conversation, list)
    end
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("awaiting_llm"), do: :awaiting_llm
  defp status_to_atom("awaiting_tool"), do: :awaiting_tool
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @doc """
  Creates a machine from a map (e.g., from strategy state storage).

  Handles both thread-based and legacy conversation-based storage.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      status: parse_status(map[:status]),
      iteration: Map.get(map, :iteration, 0),
      thread: restore_thread(map),
      pending_tool_calls: Map.get(map, :pending_tool_calls, []),
      result: Map.get(map, :result),
      active_request_id: Map.get(map, :active_request_id),
      current_llm_call_id: Map.get(map, :current_llm_call_id),
      termination_reason: Map.get(map, :termination_reason),
      cancel_reason: Map.get(map, :cancel_reason),
      streaming_text: Map.get(map, :streaming_text, ""),
      streaming_thinking: Map.get(map, :streaming_thinking, ""),
      thinking_trace: Map.get(map, :thinking_trace, []),
      usage: Map.get(map, :usage, %{}),
      started_at: Map.get(map, :started_at)
    }
  end

  # Restore thread from storage - prefer thread struct if present, otherwise rebuild from conversation
  defp restore_thread(map) do
    case map[:thread] do
      %Thread{} = thread ->
        thread

      nil ->
        # Try to rebuild from conversation list (legacy support)
        case Map.get(map, :conversation, []) do
          [] -> nil
          messages when is_list(messages) -> rebuild_thread_from_messages(messages)
        end

      _ ->
        nil
    end
  end

  # Rebuild a thread from a list of messages (for backward compatibility)
  defp rebuild_thread_from_messages([]) do
    nil
  end

  defp rebuild_thread_from_messages(messages) do
    # Check if first message is system prompt
    {system_prompt, rest} =
      case messages do
        [%{role: :system, content: content} | rest] -> {content, rest}
        [%{role: "system", content: content} | rest] -> {content, rest}
        _ -> {nil, messages}
      end

    Thread.new(system_prompt: system_prompt)
    |> Thread.append_messages(rest)
  end

  defp parse_status(s) when is_atom(s), do: Atom.to_string(s)
  defp parse_status(s) when is_binary(s), do: s
  defp parse_status(_), do: "idle"

  # Private helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp handle_llm_response(machine, {:error, reason}, env) do
    duration_ms = calculate_duration(machine)

    # Emit complete telemetry for error
    emit_telemetry(
      :complete,
      %{duration: duration_ms},
      %{
        iteration: machine.iteration,
        termination_reason: :error,
        error: reason,
        usage: machine.usage,
        thread_id: thread_id(machine)
      },
      env
    )

    emit_request_event(
      :failed,
      %{duration_ms: duration_ms},
      %{
        request_id: machine.active_request_id,
        run_id: machine.active_request_id,
        termination_reason: :error,
        error_type: :llm_error
      },
      env
    )

    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, "Error: #{inspect(reason)}")

      {machine, []}
    end)
  end

  defp handle_llm_response(machine, {:ok, result}, env) do
    machine = accumulate_usage(machine, result)
    machine = capture_thinking_to_trace(machine, Map.get(result, :thinking_content))

    case result.type do
      :tool_calls -> handle_tool_calls(machine, result.tool_calls, env)
      :final_answer -> handle_final_answer(machine, result.text, env)
    end
  end

  # Accumulates usage from LLM response into machine state
  defp accumulate_usage(machine, result) do
    case Map.get(result, :usage) do
      nil ->
        machine

      new_usage when is_map(new_usage) ->
        current = machine.usage

        merged =
          Map.merge(current, new_usage, fn _k, v1, v2 ->
            (v1 || 0) + (v2 || 0)
          end)

        %{machine | usage: merged}
    end
  end

  defp capture_thinking_to_trace(machine, classified_thinking \\ nil) do
    thinking = pick_thinking(machine.streaming_thinking, classified_thinking)

    case thinking do
      nil ->
        machine

      content ->
        entry = %{
          call_id: machine.current_llm_call_id,
          iteration: machine.iteration,
          thinking: content
        }

        %{machine | thinking_trace: machine.thinking_trace ++ [entry]}
    end
  end

  defp pick_thinking("", nil), do: nil
  defp pick_thinking("", classified) when is_binary(classified) and classified != "", do: classified
  defp pick_thinking(streaming, _) when is_binary(streaming) and streaming != "", do: streaming
  defp pick_thinking(_, _), do: nil

  defp thinking_opts(%{streaming_thinking: thinking}) when is_binary(thinking) and thinking != "" do
    [thinking: thinking]
  end

  defp thinking_opts(_), do: []

  defp handle_tool_calls(machine, tool_calls, _env) do
    # Format tool_calls for Thread storage
    formatted_tool_calls =
      Enum.map(tool_calls, fn tc ->
        %{id: tc.id, name: tc.name, arguments: tc.arguments}
      end)

    pending =
      Enum.map(tool_calls, fn tc ->
        %{id: tc.id, name: tc.name, arguments: tc.arguments, result: nil}
      end)

    with_transition(machine, "awaiting_tool", fn machine ->
      thinking_opts = thinking_opts(machine)
      thread = Thread.append_assistant(machine.thread, "", formatted_tool_calls, thinking_opts)

      machine =
        machine
        |> Map.put(:thread, thread)
        |> Map.put(:pending_tool_calls, pending)

      directives =
        Enum.map(tool_calls, fn tc ->
          {:exec_tool, tc.id, tc.name, tc.arguments}
        end)

      {machine, directives}
    end)
  end

  defp handle_final_answer(machine, answer, env) do
    duration_ms = calculate_duration(machine)

    # Emit complete telemetry for final answer
    emit_telemetry(
      :complete,
      %{duration: duration_ms},
      %{
        iteration: machine.iteration,
        termination_reason: :final_answer,
        usage: machine.usage,
        thread_id: thread_id(machine)
      },
      env
    )

    emit_request_event(
      :complete,
      %{duration_ms: duration_ms},
      %{
        request_id: machine.active_request_id,
        run_id: machine.active_request_id,
        termination_reason: :final_answer,
        error_type: nil
      },
      env
    )

    with_transition(machine, "completed", fn machine ->
      thinking_opts = thinking_opts(machine)
      thread = Thread.append_assistant(machine.thread, answer, nil, thinking_opts)

      machine =
        machine
        |> Map.put(:termination_reason, :final_answer)
        |> Map.put(:thread, thread)
        |> Map.put(:result, answer)

      {machine, []}
    end)
  end

  defp record_tool_result(machine, call_id, result) do
    pending =
      Enum.map(machine.pending_tool_calls, fn tc ->
        if tc.id == call_id, do: %{tc | result: result}, else: tc
      end)

    all_complete? = Enum.all?(pending, &(&1.result != nil))
    {%{machine | pending_tool_calls: pending}, all_complete?}
  end

  defp append_all_tool_results(machine) do
    # Append all tool results to thread
    thread =
      Enum.reduce(machine.pending_tool_calls, machine.thread, fn tc, thread ->
        content = Turn.format_tool_result_content(tc.result)
        Thread.append_tool_result(thread, tc.id, tc.name, content)
      end)

    machine
    |> Map.put(:thread, thread)
    |> Map.put(:pending_tool_calls, [])
  end

  defp inc_iteration(machine), do: Map.update!(machine, :iteration, &(&1 + 1))

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "call_#{Jido.Util.generate_id()}"
  end

  @spec generate_call_id(String.t() | nil) :: String.t()
  def generate_call_id(request_id) when is_binary(request_id) do
    "call_#{request_id}_#{Jido.Util.generate_id()}"
  end

  def generate_call_id(nil) do
    generate_call_id()
  end

  @doc """
  Returns the thread from the machine, if any.
  """
  @spec get_thread(t()) :: Thread.t() | nil
  def get_thread(%__MODULE__{thread: thread}), do: thread

  @doc """
  Returns the conversation history as a list of messages.

  This is a convenience function that projects the thread to ReqLLM format.
  """
  @spec get_conversation(t()) :: [map()]
  def get_conversation(%__MODULE__{thread: nil}), do: []
  def get_conversation(%__MODULE__{thread: thread}), do: Thread.to_messages(thread)

  # Telemetry helpers

  defp emit_telemetry(event, measurements, metadata, env) do
    obs_cfg = Map.get(env, :observability, %{})

    telemetry_metadata =
      env
      |> Map.get(:telemetry_metadata, %{})
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    merged_metadata =
      metadata
      |> Map.merge(telemetry_metadata)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Observe.emit(obs_cfg, Observe.strategy(:react, event), measurements, merged_metadata)
  end

  defp emit_request_event(event, measurements, metadata, env) do
    obs_cfg = Map.get(env, :observability, %{})
    Observe.emit(obs_cfg, Observe.request(event), measurements, metadata)
  end

  defp thread_id(%{thread: %{id: id}}) when is_binary(id), do: id
  defp thread_id(_), do: nil

  defp calculate_duration(%{started_at: nil}), do: 0

  defp calculate_duration(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
