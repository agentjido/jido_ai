defmodule Jido.AI.History do
  @moduledoc "Projects portable domain message maps through the existing AI context."
  alias Jido.AI.{Context, Profile}
  @refs_key :jido_ai_refs

  def entries(messages) do
    Context.new()
    |> Context.append_messages(Enum.map(messages, &restore_refs/1))
    |> Map.fetch!(:entries)
    |> Enum.reverse()
    |> Enum.map(&Map.from_struct/1)
  end

  def query(query, refs),
    do: entries([%{role: :user, content: query, refs: Jido.AI.Skill.Runtime.untrusted_refs(refs)}])

  def refs(record, source) do
    %{request_id: record.id, run_id: record.run_id}
    |> Map.merge(record.extra_refs)
    |> Map.put(:source, source)
    |> Jido.AI.Skill.Runtime.untrusted_refs()
  end

  def read(_state, %{memory: %{history: nil}}), do: {:ok, []}

  def read(state, profile) when is_map(state) do
    case Map.get(state, profile.memory.history) do
      values when is_list(values) ->
        if Enum.all?(values, &is_map/1),
          do: {:ok, values},
          else: Profile.error("memory.history", "Expected message maps")

      _ ->
        Profile.error("memory.history", "Expected a list of message maps")
    end
  end

  def read(_, _), do: Profile.error("memory.history", "Expected initialized Agent state")

  @doc false
  def replace(agent, profile, entries) do
    with {:ok, values} <- prepare_entries(entries),
         do: Jido.Agent.set(agent, %{profile.memory.history => values})
  end

  @doc false
  def prepare_entries(entries) do
    Jido.AI.Error.capture(fn ->
      with true <- is_list(entries) and Enum.all?(entries, &is_map/1),
           values = Enum.map(Enum.reverse(entries), &entry_map/1),
           :ok <- Jido.Action.validate_static_data(values),
           {:ok, messages} <- messages(values),
           :ok <- validate_messages(messages) do
        {:ok, values}
      else
        false -> Profile.error("memory.history", "Expected Context entries or message maps")
        {:error, _} = error -> error
      end
    end)
  end

  defp entry_map(%Context.Entry{} = entry), do: Map.from_struct(entry)
  defp entry_map(entry), do: entry

  defp validate_messages(messages) do
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case Zoi.parse(ReqLLM.Message.schema(), message) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, Profile.error("memory.history", "Invalid model message")}
      end
    end)
  end

  # A complete exchange has one result for every announced call. A pending
  # after-model pause is the only supported position with an open exchange.
  @doc false
  def open_tool_calls(messages) do
    Enum.reduce_while(messages, {:ok, %{}}, fn message, {:ok, open} ->
      case advance_history(message, open) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp advance_history(%{role: :tool, tool_call_id: id, name: name}, open) do
    case open[id] do
      %{name: expected} when name in [nil, expected] -> {:ok, Map.delete(open, id)}
      _ -> {:error, :invalid_tool_history}
    end
  end

  defp advance_history(%{role: :assistant} = message, open) when map_size(open) == 0 do
    calls = Enum.map(message.tool_calls || [], &ReqLLM.ToolCall.to_map/1)
    ids = Enum.map(calls, & &1.id)

    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and ids == Enum.uniq(ids),
      do: {:ok, Map.new(calls, &{&1.id, &1})},
      else: {:error, :invalid_tool_history}
  end

  defp advance_history(_, open) when map_size(open) == 0, do: {:ok, open}
  defp advance_history(_, _), do: {:error, :invalid_tool_history}

  def messages(entries) do
    values = Context.new() |> Context.append_messages(entries) |> Context.to_messages()
    with {:ok, context} <- normalize_messages(values), do: {:ok, context.messages}
  end

  # ReqLLM message metadata carries refs locally. Provider requests remove this
  # private key; response contexts restore only an exact matching input prefix.
  def normalize_messages(messages),
    do: ReqLLM.Context.normalize(Enum.map(messages, &carry_refs/1))

  def provider_context(%ReqLLM.Context{} = context),
    do: %{context | messages: Enum.map(context.messages, &clear_refs/1)}

  def provider_context(context), do: context

  def restore_response_context(
        %ReqLLM.Response{context: %ReqLLM.Context{messages: messages} = context} = response,
        %ReqLLM.Context{messages: sent},
        %ReqLLM.Context{messages: original}
      ) do
    {prefix, suffix} = Enum.split(messages, length(sent))

    if prefix == sent,
      do: %{response | context: %{context | messages: original ++ suffix}},
      else: response
  end

  def restore_response_context(response, _, _), do: response

  def bind_message(message, context, extra_refs \\ %{}) do
    refs =
      case context[:jido_ai_request_record] do
        nil -> extra_refs
        record -> Map.merge(refs(record, context.jido_ai_input_source), extra_refs)
      end

    put_refs(message, refs)
  end

  def bind_response(%ReqLLM.Response{message: %ReqLLM.Message{} = original} = response, context) do
    message = original |> clear_refs() |> bind_message(context)

    updated =
      case response.context do
        %ReqLLM.Context{messages: messages} = conversation ->
          case List.pop_at(messages, -1) do
            {^original, prefix} -> %{conversation | messages: prefix ++ [message]}
            _ -> conversation
          end

        other ->
          other
      end

    %{response | message: message, context: updated}
  end

  def bind_response(response, _), do: response

  defp carry_refs(%ReqLLM.Message{} = message), do: message

  defp carry_refs(message) when is_map(message),
    do: put_refs(message, Map.get(message, :refs, Map.get(message, "refs", %{})))

  defp carry_refs(message), do: message

  defp put_refs(message, refs) when is_map(refs) and map_size(refs) > 0 do
    key = if Map.has_key?(message, "role") and not Map.has_key?(message, :role), do: "metadata", else: :metadata
    Map.update(message, key, %{@refs_key => refs}, &Map.put(&1, @refs_key, refs))
  end

  defp put_refs(message, _), do: message

  defp clear_refs(%ReqLLM.Message{metadata: metadata} = message),
    do: %{message | metadata: Map.drop(metadata, [@refs_key, Atom.to_string(@refs_key)])}

  defp restore_refs(%ReqLLM.Message{metadata: %{@refs_key => refs}} = message),
    do: message |> Map.from_struct() |> Map.put(:refs, refs)

  defp restore_refs(message), do: message

  def start(state, profile, record, source) do
    with {:ok, _} <- read(state, profile),
         do: {:ok, append(state, profile, query(record.query, refs(record, source)))}
  end

  def append(state, %{memory: %{history: nil}}, _), do: state

  def append(state, profile, entries),
    do: Map.update!(state, profile.memory.history, &(&1 ++ entries))

  def record(state, entries, context) do
    entries =
      case context[:jido_ai_request_record] do
        nil ->
          entries

        record ->
          refs = refs(record, context.jido_ai_input_source)

          Enum.map(
            entries,
            &Map.update(&1, :refs, refs, fn existing -> Map.merge(refs, existing || %{}) end)
          )
      end

    result =
      if Map.get(context, :jido_ai_session, false) and state.profile.memory.history != nil,
        do: Jido.AI.Session.publish_history(context, entries),
        else: :ok

    with :ok <- result, do: {:ok, %{state | history_delta: state.history_delta ++ entries}}
  end
end

defmodule Jido.AI.Runtime.PendingInput do
  @moduledoc false
  alias Jido.AI.{History, PendingInputServer, Session}

  def seal(context) do
    case context[:jido_ai_input_queue] do
      nil -> :ok
      queue -> PendingInputServer.seal(queue)
    end
  end

  def seal_if_empty(context) do
    case context[:jido_ai_input_queue] do
      nil -> :sealed
      queue -> PendingInputServer.seal_if_empty(queue) |> queue_result(context)
    end
  end

  def drain(state, context) do
    result =
      case context[:jido_ai_input_queue] do
        nil ->
          {:ok, []}

        queue ->
          case PendingInputServer.drain_result(queue) |> queue_result(context) do
            {:ok, _} = result -> result
            {:error, reason} -> {:error, {:pending_input_server, reason}}
          end
      end

    with {:ok, items} <- result, do: consume(state, items, context)
  end

  defp queue_result({:error, _} = error, context) do
    :ok = Session.failure_type(context, :runtime)
    error
  end

  defp queue_result(result, _), do: result

  defp consume(state, [], _context), do: {:ok, state}

  defp consume(state, items, context) do
    {_, id, run_id} = context.jido_ai_events

    entries =
      Enum.flat_map(items, fn item ->
        refs =
          %{request_id: id, run_id: run_id}
          |> Map.merge(item.refs || %{})
          |> Map.put(:source, item.source)

        History.query(item.content, refs)
      end)

    with {:ok, state} <- History.record(state, entries, context) do
      Enum.reduce_while(Enum.zip(items, entries), {:ok, state}, fn {item, entry}, {:ok, state} ->
        case Session.emit(context, :input_injected, %{
               input_id: item.id,
               content: item.content,
               source: item.source,
               refs: item.refs,
               at_ms: item.at_ms
             }) do
          :ok ->
            message = History.bind_message(ReqLLM.Context.user(item.content), context, entry.refs)
            messages = ReqLLM.Context.append(state.messages, message)
            {:cont, {:ok, %{state | messages: messages}}}

          error ->
            {:halt, error}
        end
      end)
    end
  end
end

defmodule Jido.AI.Session.HistoryAction do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_history",
    schema: Zoi.object(%{request_id: Zoi.string(), batch_id: Zoi.string()})

  alias Jido.AI.Session.Change

  def run(%{request_id: id, batch_id: batch_id}, context) do
    with %{status: :pending, run_id: run_id} = record <- context.agent_state.requests[id],
         %{run_id: ^run_id, entries: entries} = batch <- context[:jido_ai_history_batch] do
      profile = context.jido_ai_profiles[record.profile_id]
      candidate = Jido.AI.History.append(context.agent_state, profile, entries)
      record = record |> Map.put(:inspection, batch.inspection) |> Map.put(:meta, batch.meta)
      record = Jido.AI.Session.Inspection.fit(record, candidate, context)

      changes =
        Jido.AI.Context.Operations.capture(
          context.agent_state,
          profile,
          entries,
          context.jido_ai_agent.id,
          record
        )

      {:ok, candidate, [%Change{operation: :history, record: record, batch_id: batch_id} | changes]}
    else
      _ -> {:error, :stale_history}
    end
  end
end

defmodule Jido.AI.Session.ControlAction do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_control",
    schema:
      Zoi.object(%{
        control_id: Zoi.string(),
        kind: Zoi.enum([:steer, :inject]),
        content: Zoi.string(),
        expected_request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
        source: Zoi.string() |> Zoi.default("/ai/react"),
        extra_refs: Zoi.map() |> Zoi.default(%{})
      })

  def run(input, context) do
    with :ok <- Jido.Action.validate_static_data(input),
         %{status: :queued, request_id: id} = result <-
           GenServer.call(context.jido_ai_session_runtime, {:control, input}) do
      record = Map.put(context.agent_state.requests[id], :last_control, result)
      {:ok, context.agent_state, [%Jido.AI.Session.Change{operation: :control, record: record}]}
    else
      %{status: :rejected} = result ->
        {:error, Jido.Action.Error.validation_error("AI control rejected", %{control: result})}

      {:error, _} = error ->
        error
    end
  end
end
