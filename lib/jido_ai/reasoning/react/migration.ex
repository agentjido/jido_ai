defmodule Jido.AI.Reasoning.ReAct.Migration do
  @moduledoc false
  alias Jido.AI.{Context, ToolCatalog}
  alias Jido.AI.Reasoning.ReAct.{Authoring, Checkpoint, Config, State}

  @required [:phase, :counters, :domain, :remaining_ms]
  @counter_keys [:iterations, :model_calls, :tool_calls]
  @terminal [:completed, :failed, :cancelled]

  def convert(saved, config, evidence) do
    config = if is_struct(config, Config), do: config, else: Config.new(config)

    with :ok <- static(saved),
         {:ok, state} <- State.from_checkpoint_map(saved),
         :ok <- check(state.version == 3, :unsupported_state_version),
         :ok <- check(state.checkpoint == nil, :already_native),
         :ok <- check(state.seq >= 0 and state.iteration >= 1, :invalid_counters),
         {:ok, evidence} <- evidence(evidence),
         {:ok, messages} <- ReqLLM.Context.normalize(Context.to_messages(state.context)),
         :ok <- validate_messages(messages.messages),
         {:ok, open} <- tool_history(messages.messages),
         :ok <- position(state, evidence, messages.messages, open),
         :ok <- termination(state, evidence),
         :ok <- counters(state, evidence, messages.messages),
         {:ok, tools} <- tools(state, config),
         {:ok, data} <- data(state, config, evidence, messages, tools),
         {:ok, state} <- Checkpoint.import_legacy(state, data, config) do
      {:ok, state}
    else
      {:error, {:state_migration, _}} = error -> error
      {:error, reason} -> error(reason)
    end
  rescue
    _ -> error(:invalid_state_or_evidence)
  end

  defp evidence(value) do
    with true <- Keyword.keyword?(value),
         true <- length(Keyword.keys(value)) == length(Enum.uniq(Keyword.keys(value))),
         true <- @required -- Keyword.keys(value) == [],
         true <- Keyword.keys(value) -- (@required ++ [:termination_reason]) == [],
         value = Map.new(value),
         true <- value.phase in [:before_llm, :after_llm, :after_tools, :terminal],
         true <- is_integer(value.remaining_ms) and value.remaining_ms >= 0,
         true <- is_map(value.domain) and not is_struct(value.domain),
         true <-
           Enum.all?(
             Map.keys(value.domain),
             &(is_atom(&1) and
                 &1 not in [
                   :messages,
                   :requests,
                   Jido.AI.Configuration.key(),
                   Jido.AI.Context.Operations.key()
                 ])
           ),
         true <-
           is_map(value.counters) and
             Enum.sort(Map.keys(value.counters)) == Enum.sort(@counter_keys),
         true <-
           Enum.all?(@counter_keys, &(is_integer(value.counters[&1]) and value.counters[&1] >= 0)),
         true <-
           value[:termination_reason] in [
             nil,
             :final_answer,
             :max_iterations,
             :failed,
             :cancelled
           ],
         :ok <- static(value) do
      {:ok, value}
    else
      _ -> error(:invalid_evidence)
    end
  end

  defp validate_messages(messages) do
    check(
      Enum.all?(messages, &match?({:ok, _}, Zoi.parse(ReqLLM.Message.schema(), &1))),
      :invalid_history
    )
  end

  defp tool_history(messages) do
    case Jido.AI.History.open_tool_calls(messages) do
      {:ok, open} -> {:ok, open}
      {:error, reason} -> error(reason)
    end
  end

  defp position(state, %{phase: :after_llm}, messages, open) do
    last = List.last(messages)

    with :ok <-
           check(
             state.status in [:running, :awaiting_tools] and match?(%{role: :assistant}, last),
             :invalid_position
           ),
         :ok <-
           check(
             Enum.all?(
               state.pending_tool_calls,
               &(&1.status == :pending and &1.attempts == 0 and is_nil(&1.result))
             ),
             :uncertain_tool_execution
           ),
         :ok <-
           check(
             state.pending_tool_calls == [] or pending_match?(state.pending_tool_calls, open),
             :invalid_pending_tools
           ) do
      :ok
    end
  end

  defp position(state, %{phase: phase}, messages, open) do
    with :ok <- check(map_size(open) == 0, :unresolved_tool_calls),
         :ok <- check(state.pending_tool_calls == [], :uncertain_tool_execution),
         :ok <-
           check(
             if(phase == :terminal,
               do: state.status in @terminal,
               else: state.status == :running
             ),
             :invalid_position
           ),
         :ok <-
           check(
             phase != :after_tools or match?(%{role: :tool}, List.last(messages)),
             :invalid_position
           ) do
      :ok
    end
  end

  defp pending_match?(pending, open) do
    Map.new(pending, &{&1.id, Map.take(&1, [:id, :name, :arguments])}) == open and
      length(pending) == map_size(open)
  end

  defp termination(state, evidence) do
    allowed =
      case {evidence.phase, state.status} do
        {:terminal, :completed} -> [nil, :final_answer, :max_iterations]
        {:terminal, status} -> [nil, status]
        _ -> [nil]
      end

    check(evidence[:termination_reason] in allowed, :invalid_termination_reason)
  end

  defp counters(state, evidence, messages) do
    counts = evidence.counters

    position =
      Checkpoint.iteration(%{
        phase: evidence.phase,
        runtime: Map.put(counts, :termination_reason, evidence[:termination_reason])
      })

    with :ok <- check(counts.model_calls >= counts.iterations, :invalid_counters),
         :ok <-
           check(
             counts.model_calls >= Enum.count(messages, &(&1.role == :assistant)),
             :invalid_counters
           ),
         :ok <-
           check(
             counts.tool_calls >= Enum.count(messages, &(&1.role == :tool)),
             :invalid_counters
           ),
         :ok <-
           check(
             evidence.phase not in [:after_llm, :after_tools] or counts.iterations > 0,
             :invalid_counters
           ),
         :ok <-
           check(
             state.iteration == position or
               (evidence.phase == :terminal and state.status in [:failed, :cancelled]),
             :invalid_counters
           ) do
      :ok
    end
  end

  defp tools(state, config) do
    with :ok <-
           check(
             Enum.all?(state.active_tools, fn {name, target} -> config.tools[name] == target end),
             :tool_catalog_changed
           ) do
      input = if map_size(state.active_tools) == 0, do: config.tools, else: state.active_tools
      ToolCatalog.from_input(input, Authoring.tool_defaults(config))
    end
  end

  defp data(state, config, evidence, messages, tools) do
    runtime =
      Map.merge(evidence.counters, %{
        messages: messages,
        history_delta: state.context.entries |> Enum.reverse() |> Enum.map(&Map.from_struct/1),
        repairs: 0,
        usage: state.usage,
        llm_call_id: state.llm_call_id,
        active_tools: tools,
        tool_meta: %{prev_tool_signature: state.prev_tool_signature}
      })

    runtime =
      if evidence[:termination_reason],
        do: Map.put(runtime, :termination_reason, evidence.termination_reason),
        else: runtime

    runtime =
      if evidence.phase == :terminal,
        do: Map.put(runtime, :output_meta, state.output) |> Map.put(:output_raw, state.result),
        else: runtime

    runtime =
      if evidence.phase in [:after_llm, :after_tools] do
        message = messages.messages |> Enum.reverse() |> Enum.find(&(&1.role == :assistant))

        response = %ReqLLM.Response{
          id: state.llm_response_id || "migrated:#{state.run_id}",
          model: Jido.AI.Runtime.ModelCall.label(config.model),
          message: message,
          context: messages,
          usage: %{},
          finish_reason: if(message.tool_calls in [nil, []], do: :stop, else: :tool_calls)
        }

        Map.put(runtime, :response, response)
      else
        runtime
      end

    {:ok,
     %{
       version: 2,
       phase: evidence.phase,
       runtime: runtime,
       domain: evidence.domain,
       effects: [],
       remaining_ms: evidence.remaining_ms,
       binding: nil
     }}
  end

  defp static(value) do
    case Jido.Action.validate_static_data(value) do
      :ok -> :ok
      _ -> error(:nonportable_data)
    end
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: error(reason)
  defp error(reason), do: {:error, {:state_migration, reason}}
end
