defmodule Jido.AI.Strategies.ChainOfThought do
  @moduledoc """
  Chain-of-Thought strategy delegated to an internal per-parent worker agent.

  The parent strategy remains the orchestration boundary while a lazily spawned
  child worker (`:cot_worker`) owns runtime execution and streaming.

  ## Delegation Model

  1. Parent receives `"ai.cot.query"` and prepares worker payload.
  2. Parent lazily spawns internal worker on first request (if needed).
  3. Parent emits `"ai.cot.worker.start"` to worker.
  4. Worker performs one CoT LLM turn and emits `"ai.cot.worker.event"` envelopes.
  5. Parent applies worker events to CoT state and preserves external API.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.ChainOfThought.Machine
  alias Jido.AI.Directive
  alias Jido.AI.Signal
  alias Jido.AI.Strategy.StateOpsHelpers

  @type config :: %{
          system_prompt: String.t(),
          model: String.t(),
          request_policy: :reject,
          llm_timeout_ms: pos_integer() | nil,
          runtime_task_supervisor: pid() | atom() | nil,
          observability: map(),
          runtime_adapter: true
        }

  @default_model "anthropic:claude-haiku-4-5"
  @worker_tag :cot_worker
  @request_trace_cap 2000
  @source "/ai/cot/strategy"

  @start :cot_start
  @llm_result :cot_llm_result
  @llm_partial :cot_llm_partial
  @request_error :cot_request_error
  @worker_event :cot_worker_event
  @worker_child_started :cot_worker_child_started
  @worker_child_exit :cot_worker_child_exit

  @doc "Returns the action atom for starting a CoT reasoning session."
  @spec start_action() :: :cot_start
  def start_action, do: @start

  @doc "Returns the legacy action atom for handling LLM results (no-op in delegated mode)."
  @spec llm_result_action() :: :cot_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the legacy action atom for handling streaming LLM partial tokens (no-op in delegated mode)."
  @spec llm_partial_action() :: :cot_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :cot_request_error
  def request_error_action, do: @request_error

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start a delegated Chain-of-Thought reasoning session",
      name: "cot.start"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "cot.request_error"
    },
    @worker_event => %{
      schema: Zoi.object(%{request_id: Zoi.string(), event: Zoi.map()}),
      doc: "Handle delegated CoT worker runtime event envelopes",
      name: "ai.cot.worker.event"
    },
    @worker_child_started => %{
      schema:
        Zoi.object(%{
          parent_id: Zoi.string() |> Zoi.optional(),
          child_id: Zoi.string() |> Zoi.optional(),
          child_module: Zoi.any() |> Zoi.optional(),
          tag: Zoi.any(),
          pid: Zoi.any(),
          meta: Zoi.map() |> Zoi.default(%{})
        }),
      doc: "Handle CoT worker child started lifecycle signal",
      name: "jido.agent.child.started"
    },
    @worker_child_exit => %{
      schema:
        Zoi.object(%{
          tag: Zoi.any(),
          pid: Zoi.any(),
          reason: Zoi.any()
        }),
      doc: "Handle CoT worker child exit lifecycle signal",
      name: "jido.agent.child.exit"
    },
    # Legacy compatibility actions kept as no-op adapters.
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Legacy no-op in delegated CoT mode",
      name: "cot.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Legacy no-op in delegated CoT mode",
      name: "cot.llm_partial"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.cot.query", {:strategy_cmd, @start}},
      {"ai.cot.worker.event", {:strategy_cmd, @worker_event}},
      {"jido.agent.child.started", {:strategy_cmd, @worker_child_started}},
      {"jido.agent.child.exit", {:strategy_cmd, @worker_child_exit}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})
    status = map_status(state[:status])

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: state[:result],
      details: build_details(state)
    }
  end

  defp map_status(:completed), do: :success
  defp map_status(:error), do: :failure
  defp map_status(:idle), do: :idle
  defp map_status(_), do: :running

  defp build_details(state) do
    trace_summary =
      state
      |> Map.get(:request_traces, %{})
      |> Enum.map(fn {request_id, trace} ->
        {request_id, %{events: length(trace.events), truncated?: trace.truncated?}}
      end)
      |> Map.new()

    %{
      phase: state[:status],
      steps: state[:steps],
      steps_count: length(state[:steps] || []),
      conclusion: state[:conclusion],
      streaming_text: state[:streaming_text],
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at]),
      current_call_id: state[:current_call_id],
      active_request_id: state[:active_request_id],
      worker_pid: state[:cot_worker_pid],
      worker_status: state[:cot_worker_status],
      trace_summary: trace_summary
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(map) when map == %{}, do: true
  defp empty_value?(_), do: false

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)

    state =
      %{
        status: :idle,
        prompt: nil,
        steps: [],
        conclusion: nil,
        raw_response: nil,
        result: nil,
        current_call_id: nil,
        termination_reason: nil,
        streaming_text: "",
        usage: %{},
        started_at: nil,
        active_request_id: nil,
        cot_worker_pid: nil,
        cot_worker_status: :missing,
        pending_worker_start: nil,
        request_traces: %{}
      }
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    {agent, dirs_rev} =
      Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
        case process_instruction(acc_agent, instr) do
          {new_agent, new_dirs} ->
            {new_agent, Enum.reverse(new_dirs, acc_dirs)}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    normalized_action = normalize_action(action)

    case normalized_action do
      @start ->
        process_start(agent, params)

      @request_error ->
        process_request_error(agent, params)

      @worker_event ->
        process_worker_event(agent, params)

      @worker_child_started ->
        process_worker_child_started(agent, params)

      @worker_child_exit ->
        process_worker_child_exit(agent, params)

      legacy when legacy in [@llm_result, @llm_partial] ->
        {agent, []}

      _ ->
        :noop
    end
  end

  defp process_start(agent, %{prompt: prompt} = params) when is_binary(prompt) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    request_id = Map.get(params, :request_id, generate_call_id())

    if busy?(state, config) do
      directive =
        Directive.EmitRequestError.new!(%{
          request_id: request_id,
          reason: :busy,
          message: "Agent is busy (status: #{state[:status]})"
        })

      {agent, [directive]}
    else
      worker_start_payload = %{
        request_id: request_id,
        run_id: request_id,
        prompt: prompt,
        config: worker_config_from_strategy(config),
        task_supervisor: config[:runtime_task_supervisor],
        context: %{
          request_id: request_id,
          agent_id: Map.get(agent, :id),
          observability: config[:observability] || %{}
        }
      }

      {new_state, directives} = ensure_worker_start(state, worker_start_payload)

      new_state =
        new_state
        |> Map.put(:status, :reasoning)
        |> Map.put(:prompt, prompt)
        |> Map.put(:steps, [])
        |> Map.put(:conclusion, nil)
        |> Map.put(:raw_response, nil)
        |> Map.put(:result, nil)
        |> Map.put(:current_call_id, nil)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:streaming_text, "")
        |> Map.put(:usage, %{})
        |> Map.put(:started_at, System.monotonic_time(:millisecond))
        |> Map.put(:active_request_id, request_id)
        |> ensure_request_trace(request_id)

      {StratState.put(agent, new_state), directives}
    end
  end

  defp process_start(agent, _params), do: {agent, []}

  defp process_request_error(agent, %{request_id: request_id, reason: reason, message: message}) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
    {StratState.put(agent, new_state), []}
  end

  defp process_request_error(agent, _params), do: {agent, []}

  defp process_worker_event(agent, %{event: event} = params) when is_map(event) do
    state = StratState.get(agent, %{})
    event = normalize_event_map(event)
    request_id = event_field(event, :request_id, params[:request_id] || state[:active_request_id])
    state = append_trace_event(state, request_id, event)

    {new_state, signals} = apply_worker_event(state, event)
    Enum.each(signals, &Jido.AgentServer.cast(self(), &1))

    kind = event_kind(event)
    new_state = maybe_mark_worker_ready(new_state, kind)
    {StratState.put(agent, new_state), []}
  end

  defp process_worker_event(agent, _params), do: {agent, []}

  defp process_worker_child_started(agent, %{tag: tag, pid: pid}) when is_pid(pid) do
    state = StratState.get(agent, %{})

    if cot_worker_tag?(tag) do
      pending = state[:pending_worker_start]

      base_state =
        state
        |> Map.put(:cot_worker_pid, pid)
        |> Map.put(:cot_worker_status, :ready)

      if is_map(pending) do
        directive = AgentDirective.emit_to_pid(worker_start_signal(pending), pid)

        new_state =
          base_state
          |> Map.put(:pending_worker_start, nil)
          |> Map.put(:cot_worker_status, :running)

        {StratState.put(agent, new_state), [directive]}
      else
        {StratState.put(agent, base_state), []}
      end
    else
      {agent, []}
    end
  end

  defp process_worker_child_started(agent, _params), do: {agent, []}

  defp process_worker_child_exit(agent, %{tag: tag, pid: pid, reason: reason}) do
    state = StratState.get(agent, %{})

    if cot_worker_tag?(tag) do
      tracked? = worker_pid_matches?(state[:cot_worker_pid], pid)

      if tracked? do
        request_id = state[:active_request_id]

        base_state =
          state
          |> Map.put(:cot_worker_pid, nil)
          |> Map.put(:cot_worker_status, :missing)
          |> Map.put(:pending_worker_start, nil)

        if is_binary(request_id) and state[:status] == :reasoning do
          error = {:cot_worker_exit, reason}

          failure_signal =
            Signal.RequestFailed.new!(%{
              request_id: request_id,
              error: error,
              run_id: request_id
            })

          Jido.AgentServer.cast(self(), failure_signal)

          failed_state =
            base_state
            |> Map.put(:status, :error)
            |> Map.put(:termination_reason, :error)
            |> Map.put(:result, "Error: #{inspect(error)}")
            |> Map.put(:active_request_id, nil)

          {StratState.put(agent, failed_state), []}
        else
          {StratState.put(agent, base_state), []}
        end
      else
        {agent, []}
      end
    else
      {agent, []}
    end
  end

  defp apply_worker_event(state, event) do
    kind = event_kind(event)
    request_id = event_field(event, :request_id, state[:active_request_id])
    llm_call_id = event_field(event, :llm_call_id, state[:current_call_id])
    data = event_field(event, :data, %{})

    base_state =
      state
      |> Map.put(:active_request_id, request_id)
      |> Map.put(:current_call_id, llm_call_id)

    case kind do
      :request_started ->
        prompt = event_field(data, :query, "")

        started_state =
          base_state
          |> Map.put(:status, :reasoning)
          |> Map.put(:prompt, prompt)
          |> Map.put(:started_at, event_field(event, :at_ms, System.monotonic_time(:millisecond)))
          |> ensure_request_trace(request_id)

        signal = Signal.RequestStarted.new!(%{request_id: request_id, query: prompt, run_id: request_id})
        {started_state, [signal]}

      :llm_started ->
        call_id = event_field(data, :call_id, llm_call_id)
        {Map.put(base_state, :current_call_id, call_id), []}

      :llm_delta ->
        chunk_type = event_field(data, :chunk_type, :content)
        delta = event_field(data, :delta, "")

        updated =
          if chunk_type == :content do
            Map.update(base_state, :streaming_text, delta, &(&1 <> delta))
          else
            base_state
          end

        signal = Signal.LLMDelta.new!(%{call_id: llm_call_id || "", delta: delta, chunk_type: chunk_type})
        {updated, [signal]}

      :llm_completed ->
        text = event_field(data, :text, "")
        usage = event_field(data, :usage, %{})
        call_id = event_field(data, :call_id, llm_call_id)

        updated =
          base_state
          |> Map.put(:raw_response, text)
          |> Map.put(:current_call_id, call_id)
          |> Map.update(:usage, usage || %{}, fn existing -> merge_usage(existing, usage || %{}) end)

        llm_signal =
          Signal.LLMResponse.new!(%{
            call_id: call_id || "",
            result:
              {:ok,
               %{
                 text: text,
                 usage: usage
               }}
          })

        usage_signal = maybe_usage_signal(call_id || "", config_model(state), usage)
        {updated, Enum.reject([llm_signal, usage_signal], &is_nil/1)}

      :request_completed ->
        text = event_field(data, :result, "")
        usage = event_field(data, :usage, %{})
        {steps, conclusion} = Machine.extract_steps_and_conclusion(text)
        result = conclusion || text

        updated =
          base_state
          |> Map.put(:status, :completed)
          |> Map.put(:steps, steps)
          |> Map.put(:conclusion, conclusion)
          |> Map.put(:raw_response, text)
          |> Map.put(:result, result)
          |> Map.put(:usage, usage || %{})
          |> Map.put(:termination_reason, :success)
          |> Map.put(:active_request_id, nil)

        signal = Signal.RequestCompleted.new!(%{request_id: request_id, result: result, run_id: request_id})
        {updated, [signal]}

      :request_failed ->
        error = event_field(data, :error, :unknown_error)

        updated =
          base_state
          |> Map.put(:status, :error)
          |> Map.put(:termination_reason, :error)
          |> Map.put(:result, "Error: #{inspect(error)}")
          |> Map.put(:active_request_id, nil)

        signal = Signal.RequestFailed.new!(%{request_id: request_id, error: error, run_id: request_id})
        {updated, [signal]}

      :request_cancelled ->
        reason = event_field(data, :reason, :cancelled)
        error = {:cancelled, reason}

        updated =
          base_state
          |> Map.put(:status, :error)
          |> Map.put(:termination_reason, :error)
          |> Map.put(:result, "Error: #{inspect(error)}")
          |> Map.put(:active_request_id, nil)

        signal = Signal.RequestFailed.new!(%{request_id: request_id, error: error, run_id: request_id})
        {updated, [signal]}

      _ ->
        {base_state, []}
    end
  end

  defp maybe_usage_signal(_call_id, _model, usage) when usage in [%{}, nil], do: nil

  defp maybe_usage_signal(call_id, model, usage) do
    input_tokens = Map.get(usage, :input_tokens, 0)
    output_tokens = Map.get(usage, :output_tokens, 0)

    Signal.Usage.new!(%{
      call_id: call_id,
      model: model || "",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    })
  end

  defp merge_usage(existing, incoming) do
    Map.merge(existing || %{}, incoming || %{}, fn _k, left, right -> (left || 0) + (right || 0) end)
  end

  defp event_kind(event) do
    case event_field(event, :kind) do
      kind when is_atom(kind) -> kind
      kind when is_binary(kind) -> runtime_kind_from_string(kind)
      _ -> :unknown
    end
  end

  defp runtime_kind_from_string("request_started"), do: :request_started
  defp runtime_kind_from_string("llm_started"), do: :llm_started
  defp runtime_kind_from_string("llm_delta"), do: :llm_delta
  defp runtime_kind_from_string("llm_completed"), do: :llm_completed
  defp runtime_kind_from_string("request_completed"), do: :request_completed
  defp runtime_kind_from_string("request_failed"), do: :request_failed
  defp runtime_kind_from_string("request_cancelled"), do: :request_cancelled
  defp runtime_kind_from_string(_), do: :unknown

  defp event_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_event_map(event) when is_map(event), do: event

  defp config_model(state) do
    state
    |> Map.get(:config, %{})
    |> Map.get(:model)
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp busy?(state, config) do
    config[:request_policy] == :reject and state[:status] == :reasoning and is_binary(state[:active_request_id])
  end

  defp ensure_worker_start(state, worker_start_payload) do
    if is_pid(state[:cot_worker_pid]) and Process.alive?(state[:cot_worker_pid]) do
      directive = AgentDirective.emit_to_pid(worker_start_signal(worker_start_payload), state[:cot_worker_pid])

      new_state =
        state
        |> Map.put(:pending_worker_start, nil)
        |> Map.put(:cot_worker_status, :running)

      {new_state, [directive]}
    else
      spawn_directive = AgentDirective.spawn_agent(Jido.AI.Agents.Internal.CoTWorkerAgent, @worker_tag)

      new_state =
        state
        |> Map.put(:cot_worker_pid, nil)
        |> Map.put(:cot_worker_status, :starting)
        |> Map.put(:pending_worker_start, worker_start_payload)

      {new_state, [spawn_directive]}
    end
  end

  defp worker_start_signal(payload) do
    Jido.Signal.new!("ai.cot.worker.start", payload, source: @source)
  end

  defp cot_worker_tag?(tag), do: tag == @worker_tag or tag == Atom.to_string(@worker_tag)

  defp worker_pid_matches?(expected, actual) when is_pid(expected) and is_pid(actual), do: expected == actual
  defp worker_pid_matches?(_expected, _actual), do: true

  defp maybe_mark_worker_ready(state, kind) when kind in [:request_completed, :request_failed, :request_cancelled] do
    Map.put(state, :cot_worker_status, :ready)
  end

  defp maybe_mark_worker_ready(state, _kind), do: state

  defp ensure_request_trace(state, request_id) when is_binary(request_id) do
    traces = Map.get(state, :request_traces, %{})
    trace = Map.get(traces, request_id, %{events: [], truncated?: false})
    Map.put(state, :request_traces, Map.put(traces, request_id, trace))
  end

  defp ensure_request_trace(state, _request_id), do: state

  defp append_trace_event(state, request_id, event) when is_binary(request_id) do
    traces = Map.get(state, :request_traces, %{})
    trace = Map.get(traces, request_id, %{events: [], truncated?: false})

    updated_trace =
      cond do
        trace.truncated? ->
          trace

        length(trace.events) < @request_trace_cap ->
          %{trace | events: trace.events ++ [event]}

        true ->
          %{trace | truncated?: true}
      end

    Map.put(state, :request_traces, Map.put(traces, request_id, updated_trace))
  end

  defp append_trace_event(state, _request_id, _event), do: state

  defp worker_config_from_strategy(config) do
    %{
      model: config[:model],
      system_prompt: config[:system_prompt],
      llm_timeout_ms: config[:llm_timeout_ms],
      capture_deltas?: get_in(config, [:observability, :emit_llm_deltas?]) != false
    }
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)
    system_prompt = Keyword.get(opts, :system_prompt, Machine.default_system_prompt())

    %{
      system_prompt: system_prompt,
      model: resolved_model,
      request_policy: :reject,
      llm_timeout_ms: Keyword.get(opts, :llm_timeout_ms),
      runtime_task_supervisor: Keyword.get(opts, :runtime_task_supervisor),
      runtime_adapter: true,
      observability:
        Map.merge(
          %{
            emit_telemetry?: true,
            emit_llm_deltas?: true
          },
          opts |> Keyword.get(:observability, %{}) |> normalize_map_opt()
        )
    }
  end

  defp normalize_map_opt(%{} = value), do: value
  defp normalize_map_opt({:%{}, _meta, pairs}) when is_list(pairs), do: Map.new(pairs)
  defp normalize_map_opt(_), do: %{}

  defp resolve_model_spec(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  defp resolve_model_spec(model) when is_binary(model), do: model

  defp generate_call_id, do: Machine.generate_call_id()

  @doc """
  Returns the extracted reasoning steps from the agent's current state.
  """
  @spec get_steps(Agent.t()) :: [Machine.step()]
  def get_steps(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:steps] || []
  end

  @doc """
  Returns the conclusion from the agent's current state.
  """
  @spec get_conclusion(Agent.t()) :: String.t() | nil
  def get_conclusion(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:conclusion]
  end

  @doc """
  Returns the raw LLM response from the agent's current state.
  """
  @spec get_raw_response(Agent.t()) :: String.t() | nil
  def get_raw_response(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:raw_response]
  end
end
