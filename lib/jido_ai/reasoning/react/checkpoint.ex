defmodule Jido.AI.Reasoning.ReAct.Checkpoint do
  @moduledoc false
  alias Jido.AI.Execution
  alias Jido.AI.Reasoning.ReAct.{Config, PendingToolCall, State}

  @behaviour Jido.AI.Execution.Checkpoint

  @impl true
  def verify(%State{checkpoint: nil}, _), do: :ok

  def verify(%State{checkpoint: data} = state, config) do
    with :ok <- validate_state(state),
         true <- data.binding == fingerprint(config, data.runtime[:active_tools] || [], data.effects) do
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
    with :ok <- Execution.Checkpoint.validate_data(data),
         true <- state.iteration == Execution.State.iteration(data.runtime, data.phase),
         {:ok, _} <- Jido.AI.Model.Messages.messages(Map.get(data.runtime, :pending_queries, [])),
         true <- Enum.all?(Map.get(data.runtime, :pending_queries, []), &(&1.role == :user)),
         true <-
           Map.get(data.runtime, :pending_queries, []) == [] or
             (data.phase == :after_llm and pending(data.runtime, :after_llm) != []),
         {:ok, messages} <- ReqLLM.Context.normalize(data.runtime.messages),
         true <-
           Enum.all?(messages.messages, &match?({:ok, _}, Zoi.parse(ReqLLM.Message.schema(), &1))),
         {:ok, _} <- Jido.AI.Model.Messages.messages(data.runtime.history_delta),
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

  @impl true
  defdelegate issue(state, config), to: Jido.AI.Reasoning.ReAct.Token

  @impl true
  def pack(native, data, %{state: initial, config: config}) do
    runtime = data.runtime
    phase = data.phase
    calls = pending(runtime, phase)

    saved = %{
      initial
      | checkpoint: data,
        context: State.context(native.history_delta, config.system_prompt),
        status: status(calls, phase),
        pending_tool_calls: calls,
        active_tools: Map.new(runtime[:active_tools] || [], &{&1.name, &1.target}),
        iteration: Execution.State.iteration(data.runtime, data.phase),
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

  def append_query(state, query, config, context, timeout) do
    with :ok <- verify(state, config),
         {:ok, data} <- continuation(state, config, context, timeout) do
      entries =
        Jido.AI.Orchestration.Transcript.query(query, %{
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
          iteration: Execution.State.iteration(data.runtime, data.phase),
          context: State.context(data.runtime.history_delta, config.system_prompt),
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
    history = State.history(state.context)

    with {:ok, messages} <- ReqLLM.Context.normalize(State.messages(state.context)) do
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
         binding: fingerprint(config, [], [])
       }}
    end
  end

  defp continuation(_, _, _, _), do: {:error, :checkpoint_phase_not_ported}

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

  @impl true
  def fingerprint(config, tools, effects) do
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
