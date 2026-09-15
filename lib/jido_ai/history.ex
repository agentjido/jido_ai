defmodule Jido.AI.History do
  @moduledoc "Projects portable domain message maps through the existing AI context."
  alias Jido.AI.{Context, Conversation, Profile}
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
    record.extra_refs
    |> Map.drop([:request_id, :run_id, :signal_id, "request_id", "run_id", "signal_id"])
    |> Map.merge(%{request_id: record.id, run_id: record.run_id})
    |> Map.put(:source, source)
    |> Jido.AI.Skill.Runtime.untrusted_refs()
  end

  def read(_state, %{memory: %{history: nil}}), do: {:ok, []}

  def read(state, profile) when is_map(state) do
    case Map.get(state, profile.memory.history) do
      nil ->
        {:ok, []}

      %Jido.Session{} = session ->
        with {:ok, selected} <- Conversation.select(session) do
          {:ok,
           Enum.map(selected.entries, fn entry ->
             {:ok, message} = Conversation.message(entry)
             [value] = entries([message])
             %{value | refs: entry.refs, timestamp: DateTime.from_unix!(entry.at, :millisecond)}
           end)}
        end

      _ ->
        Profile.error("memory.history", "Expected a Jido.Session value")
    end
  end

  def read(_, _), do: Profile.error("memory.history", "Expected initialized Agent state")

  @doc false
  def replace(agent, profile, entries) do
    with {:ok, values} <- prepare_entries(entries) do
      state = append(Map.put(agent.state, profile.memory.history, nil), profile, values)
      Jido.Agent.set(agent, %{profile.memory.history => state[profile.memory.history]})
    end
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
  defdelegate open_tool_calls(messages), to: Jido.AI.Conversation

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

  def append(state, profile, entries) do
    session = Map.get(state, profile.memory.history) || Jido.Session.new()
    ref = Jido.AI.Context.Operations.active_ref(state, profile.id)

    session =
      Enum.reduce(entries, session, fn entry, session ->
        {:ok, messages} = messages([entry])
        refs = Map.put(Map.get(entry, :refs) || %{}, :context_ref, ref)
        {:ok, [canonical]} = Conversation.entries(messages, refs)

        canonical =
          case entry[:timestamp] do
            %DateTime{} = timestamp -> %{canonical | at: DateTime.to_unix(timestamp, :millisecond)}
            _ -> canonical
          end

        Jido.Session.append(session, canonical)
      end)

    Map.put(state, profile.memory.history, session)
  end

  def record(state, entries, context) do
    entries =
      case context[:jido_ai_request_record] do
        nil ->
          entries

        record ->
          refs = refs(record, context.jido_ai_input_source)

          Enum.map(
            entries,
            &Map.update(&1, :refs, refs, fn existing ->
              refs
              |> Map.merge(existing || %{})
              |> Map.drop([:signal_id, "request_id", "run_id", "signal_id"])
              |> Map.merge(%{request_id: record.id, run_id: record.run_id})
            end)
          )
      end

    result =
      if Map.get(context, :jido_ai_session, false) and state.profile.memory.history != nil,
        do: Jido.AI.Session.publish_history(context, entries),
        else: :ok

    with :ok <- result, do: {:ok, %{state | history_delta: state.history_delta ++ entries}}
  end
end
