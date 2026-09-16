defmodule Jido.AI.Execution.Checkpoint do
  @moduledoc false
  alias Jido.AI.Execution

  # An internal adapter supplies the standalone value and token format.
  # The runtime owns execution position, deadlines, effects and pause/ack.
  @callback verify(map(), term()) :: :ok | {:error, term()}
  @callback pack(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback fingerprint(term(), list(), list()) :: map()
  @callback issue(map(), term()) :: term()

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
    do:
      match?(
        %{adapter: adapter, result_key: key, config: _, state: %{checkpoint: _}}
        when is_atom(adapter) and not is_nil(adapter) and is_atom(key),
        context[:jido_ai_checkpoint]
      )

  def resumed?(context),
    do: enabled?(context) and is_map(context.jido_ai_checkpoint.state.checkpoint)

  def admission(context, id, run_id) do
    case context[:jido_ai_checkpoint] do
      nil ->
        :ok

      %{adapter: adapter, state: %{request_id: ^id, run_id: ^run_id} = state, config: config} ->
        if enabled?(context), do: adapter.verify(state, config), else: {:error, :invalid_checkpoint_binding}

      _ ->
        {:error, :invalid_checkpoint_binding}
    end
  end

  def validate_data(data) do
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
         true <- data.runtime.model_calls >= data.runtime.iterations,
         true <- data.phase in [:before_llm, :terminal] or data.runtime.iterations > 0,
         true <- not Map.has_key?(data.runtime, :output_meta) or Map.has_key?(data.runtime, :output_raw),
         true <- data.runtime.repairs == 0 or is_map(data.runtime[:repair_data]),
         true <- is_integer(data.remaining_ms) and data.remaining_ms >= 0,
         true <- valid_response?(data),
         :ok <- Jido.Action.validate_static_data(data) do
      :ok
    else
      _ -> {:error, :invalid_runtime_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_runtime_checkpoint}
  end

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
    %{adapter: adapter, config: config} = binding = context.jido_ai_checkpoint
    runtime = native |> Map.take(@runtime_keys) |> responses()

    domain =
      Map.drop(native.effect_plan.state, [
        native.profile.memory.history,
        :requests,
        Jido.AI.Configuration.key(),
        Jido.AI.Thread.Control.key()
      ])

    effects = if phase == :terminal, do: [], else: native.effect_plan.directives

    data = %{
      version: 2,
      phase: phase,
      runtime: runtime,
      domain: domain,
      effects: effects,
      remaining_ms: max(native.deadline - System.monotonic_time(:millisecond), 0),
      binding: adapter.fingerprint(config, runtime[:active_tools] || [], effects)
    }

    with :ok <- validate_data(data), do: adapter.pack(native, data, binding)
  end

  def restore(native, context) do
    if resumed?(context) do
      %{state: saved, config: config, adapter: adapter} = context.jido_ai_checkpoint
      data = saved.checkpoint

      with :ok <- adapter.verify(saved, config),
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

  def metadata(%{checkpoint: nil}), do: %{}

  def metadata(%{checkpoint: %{runtime: runtime} = data}) do
    Map.get(runtime, :response_meta, %{})
    |> Map.merge(Map.get(runtime, :tool_meta, %{}))
    |> Map.merge(Map.take(runtime, [:model_calls, :tool_calls, :usage]))
    |> Map.put(:reasoning_iteration, Execution.State.iteration(data.runtime, data.phase))
  end

  # Terminal continuation uses the same portable format as an active pause.
  # Effects have already been committed when the Runner publishes this token.
  def terminal(native, meta, context) do
    if enabled?(context) do
      with {:ok, saved} <- capture(native, :terminal, context),
           do: {:ok, Map.put(meta, context.jido_ai_checkpoint.result_key, saved.checkpoint)}
    else
      {:ok, meta}
    end
  end

  def consume_queries(state, context) do
    case Map.get(state, :pending_queries, []) do
      [] ->
        {:ok, state}

      entries ->
        with {:ok, messages} <- Jido.AI.Model.Messages.messages(entries),
             {:ok, state} <- Jido.AI.Orchestration.Transcript.record(state, entries, context) do
          messages = Enum.reduce(messages, state.messages, &ReqLLM.Context.append(&2, &1))
          {:ok, Map.merge(state, %{messages: messages, pending_queries: []})}
        end
    end
  end

  defp restore_messages(state, :before_llm, initial_messages) do
    with {:ok, history} <- Jido.AI.Model.Messages.messages(state.history_delta) do
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
    policy = Execution.ToolInterception.policy(state.profile)

    Enum.reduce_while(effects, :ok, fn effect, :ok ->
      with true <- Jido.AI.Effects.Policy.allowed?(Jido.AI.Effects.Policy.new(policy), effect),
           {:ok, _} <- Jido.AI.Effects.Candidate.validate_directive(effect, context.jido_ai_agent) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :checkpoint_effect_not_permitted}}
      end
    end)
  end

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
end
