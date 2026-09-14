defmodule Jido.AI.Reasoning.ReAct.Checkpoint do
  @moduledoc false
  alias Jido.AI.{Context, History, Runtime}
  alias Jido.AI.Reasoning.ReAct.{Config, PendingToolCall, State}

  # Store AI data only. Rebind profile, provider options, deadlines and the
  # effect-plan base in a fresh Agent. An Exec execution is never a checkpoint.
  @runtime_keys [
    :messages,
    :response,
    :history_delta,
    :iterations,
    :model_calls,
    :tool_calls,
    :repairs,
    :usage,
    :llm_call_id,
    :response_meta,
    :tool_meta,
    :output_meta,
    :output_raw,
    :object_request,
    :repair_data,
    :active_tools,
    :pending_queries,
    :termination_reason
  ]
  @required [
    :messages,
    :history_delta,
    :iterations,
    :model_calls,
    :tool_calls,
    :repairs,
    :usage
  ]
  @keys [:version, :phase, :runtime, :domain, :effects, :remaining_ms, :binding]

  def enabled?(context),
    do: match?(%{config: %Config{}, state: %State{}}, context[:jido_ai_checkpoint])

  def resumed?(context),
    do: match?(%{state: %State{checkpoint: data}} when is_map(data), context[:jido_ai_checkpoint])

  def admission(context, id, run_id) do
    case context[:jido_ai_checkpoint] do
      nil ->
        :ok

      %{config: %Config{} = config, state: %State{request_id: ^id, run_id: ^run_id} = state} ->
        verify(state, config)

      _ ->
        {:error, :invalid_checkpoint_binding}
    end
  end

  def verify(%State{checkpoint: nil}, _), do: :ok

  def verify(%State{checkpoint: data} = state, config) do
    with :ok <- validate_state(state),
         true <- data.binding == binding(config, data.runtime[:active_tools] || [], data.effects) do
      :ok
    else
      false -> {:error, :checkpoint_code_or_contract_changed}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :checkpoint_code_or_contract_changed}
  end

  def validate_state(%State{checkpoint: nil}), do: :ok

  def validate_state(%State{checkpoint: data} = state) when is_map(data) do
    with true <- Enum.sort(Map.keys(data)) == Enum.sort(@keys),
         true <- valid_phase?(data),
         true <- is_map(data.runtime) and is_map(data.domain) and is_list(data.effects),
         true <- Enum.all?(@required, &Map.has_key?(data.runtime, &1)),
         true <- Map.keys(data.runtime) -- @runtime_keys == [],
         true <-
           Enum.all?(
             [:iterations, :model_calls, :tool_calls, :repairs],
             &(is_integer(data.runtime[&1]) and data.runtime[&1] >= 0)
           ),
         true <-
           data.runtime.model_calls >= data.runtime.iterations,
         true <- data.phase in [:before_llm, :terminal] or data.runtime.iterations > 0,
         true <- state.iteration == iteration(data),
         true <-
           not Map.has_key?(data.runtime, :output_meta) or Map.has_key?(data.runtime, :output_raw),
         true <- data.runtime.repairs == 0 or is_map(data.runtime[:repair_data]),
         true <- is_integer(data.remaining_ms) and data.remaining_ms >= 0,
         true <- valid_response?(data),
         {:ok, _} <- History.messages(Map.get(data.runtime, :pending_queries, [])),
         true <- Enum.all?(Map.get(data.runtime, :pending_queries, []), &(&1.role == :user)),
         true <-
           Map.get(data.runtime, :pending_queries, []) == [] or
             (data.phase == :after_llm and pending(data.runtime, :after_llm) != []),
         {:ok, messages} <- ReqLLM.Context.normalize(data.runtime.messages),
         true <-
           Enum.all?(messages.messages, &match?({:ok, _}, Zoi.parse(ReqLLM.Message.schema(), &1))),
         {:ok, _} <- History.messages(data.runtime.history_delta),
         true <- state.usage == data.runtime.usage,
         true <-
           state.prev_tool_signature == get_in(data.runtime, [:tool_meta, :prev_tool_signature]),
         true <- state.pending_tool_calls == pending(data.runtime, data.phase),
         true <- valid_status?(state.status, state.pending_tool_calls, data.phase),
         true <- data.phase != :terminal or data.effects == [],
         :ok <- Jido.Action.validate_static_data(data) do
      :ok
    else
      _ -> {:error, :invalid_react_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_react_checkpoint}
  end

  def validate_state(_), do: {:error, :invalid_react_checkpoint}

  def pause(native, phase, context) do
    if enabled?(context) do
      with {:ok, saved} <- capture(native, phase, context),
           {runtime, id, run_id} = context.jido_ai_events,
           :ok <- GenServer.call(runtime, {:checkpoint, id, run_id, phase, saved}, :infinity) do
        {:ok, native}
      end
    else
      {:ok, native}
    end
  end

  defp capture(native, phase, context) do
    %{state: initial, config: config} = context.jido_ai_checkpoint
    runtime = native |> Map.take(@runtime_keys) |> responses()
    calls = pending(runtime, phase)

    domain =
      Map.drop(native.effect_plan.state, [
        :messages,
        :requests,
        Jido.AI.Configuration.key(),
        Jido.AI.Context.Operations.key()
      ])

    effects = if phase == :terminal, do: [], else: native.effect_plan.directives

    data = %{
      version: 2,
      phase: phase,
      runtime: runtime,
      domain: domain,
      effects: effects,
      remaining_ms: max(native.deadline - System.monotonic_time(:millisecond), 0),
      binding: binding(config, runtime[:active_tools] || [], effects)
    }

    saved = %{
      initial
      | checkpoint: data,
        context:
          Context.new(system_prompt: config.system_prompt)
          |> Context.append_messages(native.history_delta),
        status: status(calls, phase),
        pending_tool_calls: calls,
        active_tools: Map.new(runtime[:active_tools] || [], &{&1.name, &1.target}),
        iteration: iteration(data),
        llm_call_id: native[:llm_call_id],
        llm_response_id: if(native[:response], do: native.response.id),
        usage: native.usage,
        prev_tool_signature: get_in(native, [:tool_meta, :prev_tool_signature]),
        streaming_text: stream_field(native[:response], config, :text),
        streaming_thinking: stream_field(native[:response], config, :thinking),
        output: Map.get(native, :output_meta, %{}),
        result: nil,
        error: nil,
        termination_reason: native[:termination_reason],
        updated_at_ms: System.system_time(:millisecond)
    }

    with :ok <- validate_state(saved), do: {:ok, saved}
  end

  # A checkpoint is only made after a complete model response. Recover the
  # stream fields from that response; no second live accumulator is needed.
  defp stream_field(nil, _, _), do: ""

  defp stream_field(response, %{streaming: true, trace: %{capture_deltas?: true}}, kind),
    do: apply(ReqLLM.Response, kind, [response]) || ""

  defp stream_field(_, _, _), do: ""

  def restore(native, context) do
    if resumed?(context) do
      %{state: saved, config: config} = context.jido_ai_checkpoint
      data = saved.checkpoint

      with :ok <- verify(saved, config),
           true <- data.remaining_ms > 0,
           :ok <- validate_effects(data.effects, native, context) do
        plan = %{native.effect_plan | directives: data.effects}
        state = native |> Map.merge(data.runtime) |> Map.put(:effect_plan, plan)
        deadline = min(state.deadline, System.monotonic_time(:millisecond) + data.remaining_ms)

        with {:ok, state} <- restore_messages(state, data.phase, native.messages) do
          {:ok, %{state | deadline: deadline} |> Map.put(:checkpoint_phase, data.phase)}
        end
      else
        false -> {:error, :checkpoint_deadline_exhausted}
        {:error, _} = error -> error
      end
    else
      {:ok, native}
    end
  end

  def metadata(%State{checkpoint: nil}), do: %{}

  def metadata(%State{checkpoint: %{runtime: runtime} = data}) do
    Map.get(runtime, :response_meta, %{})
    |> Map.merge(Map.get(runtime, :tool_meta, %{}))
    |> Map.merge(Map.take(runtime, [:model_calls, :tool_calls, :usage]))
    |> Map.put(:reasoning_iteration, iteration(data))
  end

  # Terminal continuation uses the same portable format as an active pause.
  # Effects have already been committed when the Runner publishes this token.
  def terminal(native, meta, context) do
    if enabled?(context) do
      with {:ok, saved} <- capture(native, :terminal, context),
           do: {:ok, Map.put(meta, :react_checkpoint, saved.checkpoint)}
    else
      {:ok, meta}
    end
  end

  def iteration(%{runtime: runtime, phase: phase}) do
    if phase in [:before_llm, :after_tools] or runtime[:termination_reason] == :max_iterations,
      do: runtime.iterations + 1,
      else: max(runtime.iterations, 1)
  end

  @doc false
  def model_iteration(state) do
    if state.repairs > 0 or state[:checkpoint_phase] == :after_llm,
      do: max(state.iterations, 1),
      else: state.iterations + 1
  end

  def append_query(state, query, config, context, timeout) do
    with :ok <- verify(state, config),
         {:ok, data} <- continuation(state, config, context, timeout) do
      entries =
        History.query(query, %{
          request_id: state.request_id,
          run_id: state.run_id,
          source: "/ai/react/standalone"
        })

      data =
        if data.phase == :after_llm and pending(data.runtime, :after_llm) != [] do
          runtime = Map.update(data.runtime, :pending_queries, entries, &(&1 ++ entries))
          %{data | version: 2, runtime: runtime}
        else
          runtime =
            data.runtime
            |> Map.drop([
              :output_meta,
              :output_raw,
              :object_request,
              :repair_data,
              :termination_reason
            ])
            |> Map.put(:repairs, 0)
            |> Map.update!(:history_delta, &(&1 ++ entries))

          %{data | version: 2, phase: :before_llm, runtime: runtime}
        end

      state = %{
        state
        | checkpoint: data,
          status: status(pending(data.runtime, data.phase), data.phase),
          pending_tool_calls: pending(data.runtime, data.phase),
          iteration: iteration(data),
          context:
            Context.new(system_prompt: config.system_prompt)
            |> Context.append_messages(data.runtime.history_delta),
          result: nil,
          error: nil,
          output: %{},
          termination_reason: nil,
          updated_at_ms: System.system_time(:millisecond)
      }

      with :ok <- validate_state(state), do: {:ok, state}
    end
  end

  defp continuation(%State{checkpoint: data}, _, _, _) when is_map(data), do: {:ok, data}

  defp continuation(
         %State{status: :running, iteration: 1, seq: 0, pending_tool_calls: []} = state,
         config,
         context,
         timeout
       ) do
    history = state.context.entries |> Enum.reverse() |> Enum.map(&Map.from_struct/1)

    with {:ok, messages} <- ReqLLM.Context.normalize(Context.to_messages(state.context)) do
      {:ok,
       %{
         version: 2,
         phase: :before_llm,
         runtime: %{
           messages: messages,
           history_delta: history,
           iterations: 0,
           model_calls: 0,
           tool_calls: 0,
           repairs: 0,
           usage: state.usage
         },
         domain: Map.get(context, :state, %{}),
         effects: [],
         remaining_ms: timeout,
         binding: binding(config, [], [])
       }}
    end
  end

  defp continuation(_, _, _, _), do: {:error, :checkpoint_phase_not_ported}

  def consume_queries(state, context) do
    case Map.get(state, :pending_queries, []) do
      [] ->
        {:ok, state}

      entries ->
        with {:ok, messages} <- History.messages(entries),
             {:ok, state} <- History.record(state, entries, context) do
          messages = Enum.reduce(messages, state.messages, &ReqLLM.Context.append(&2, &1))
          {:ok, Map.merge(state, %{messages: messages, pending_queries: []})}
        end
    end
  end

  defp restore_messages(state, :before_llm, initial_messages) do
    with {:ok, history} <- History.messages(state.history_delta) do
      system = Enum.filter(initial_messages.messages, &(&1.role == :system))
      {:ok, %{state | messages: ReqLLM.Context.new(system ++ history)}}
    end
  end

  defp restore_messages(state, _, _), do: {:ok, state}

  defp valid_phase?(%{version: 2, phase: phase}),
    do: phase in [:before_llm, :after_llm, :after_tools, :terminal]

  defp valid_phase?(_), do: false

  defp valid_response?(%{phase: phase, runtime: runtime}) do
    if phase in [:after_llm, :after_tools] or Map.has_key?(runtime, :response),
      do: match?(%ReqLLM.Response{stream: nil}, runtime[:response]),
      else: true
  end

  defp validate_effects(effects, state, context) do
    policy = Runtime.ToolInterception.policy(state.profile)

    Enum.reduce_while(effects, :ok, fn effect, :ok ->
      with true <- Jido.AI.Effects.Policy.allowed?(Jido.AI.Effects.Policy.new(policy), effect),
           {:ok, _} <- Jido.AI.Effects.Candidate.validate_directive(effect, context.jido_ai_agent) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :checkpoint_effect_not_permitted}}
      end
    end)
  end

  defp pending(runtime, :after_llm),
    do:
      Enum.map(
        ReqLLM.Response.tool_calls(runtime.response),
        &(ReqLLM.ToolCall.to_map(&1) |> PendingToolCall.from_tool_call())
      )

  defp pending(_, phase) when phase in [:before_llm, :after_tools, :terminal], do: []
  defp status(_, :terminal), do: :completed
  defp status([], _), do: :running
  defp status(_, _), do: :awaiting_tools

  defp valid_status?(status, [], :terminal), do: status in [:completed, :failed, :cancelled]
  defp valid_status?(value, calls, phase), do: value == status(calls, phase)

  # Response stream handles are transport state. All other live values cause
  # static-data validation to fail instead of being silently dropped.
  defp responses(%ReqLLM.Response{} = response),
    do: response |> Map.put(:stream, nil) |> response_fields()

  defp responses(%ReqLLM.Context{} = context),
    do: context |> Map.put(:tools, []) |> response_fields()

  defp responses(value) when is_map(value), do: response_fields(value)
  defp responses(value) when is_list(value), do: Enum.map(value, &responses/1)
  defp responses(value), do: value

  defp response_fields(value),
    do: Map.new(Map.to_list(value), fn {key, value} -> {key, responses(value)} end)

  defp binding(config, tools, effects) do
    contract =
      {Config.fingerprint(config), config.tools, config.effect_policy, config.output, config.llm.max_tokens,
       config.llm.temperature, config.llm.tool_choice}

    code =
      modules([config.tools, config.output, config.request_transformer, tools, effects])
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn module ->
        Code.ensure_loaded!(module)
        {module, module.module_info(:md5)}
      end)

    %{contract: :crypto.hash(:sha256, :erlang.term_to_binary(contract)), code: code}
  end

  defp modules(value) when is_atom(value),
    do: if(String.starts_with?(Atom.to_string(value), "Elixir."), do: [value], else: [])

  defp modules(value) when is_map(value), do: value |> Map.to_list() |> modules()
  defp modules(value) when is_tuple(value), do: value |> Tuple.to_list() |> modules()
  defp modules(value) when is_list(value), do: Enum.flat_map(value, &modules/1)
  defp modules(value) when is_function(value), do: [value |> Function.info(:module) |> elem(1)]
  defp modules(_), do: []
end
