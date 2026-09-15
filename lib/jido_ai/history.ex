defmodule Jido.AI.History do
  @moduledoc "Reads and commits the Profile's canonical Session conversation."
  alias Jido.AI.{Conversation, Profile}
  @refs_key :jido_ai_refs

  def entries(messages) do
    Enum.map(messages, fn input ->
      {:ok, context} = normalize_messages([input])
      [message] = context.messages
      refs = message.metadata[@refs_key] || message.metadata[Atom.to_string(@refs_key)] || %{}

      message
      |> clear_refs()
      |> Map.from_struct()
      |> Map.put(:refs, if(refs == %{}, do: nil, else: refs))
      |> Map.put(:timestamp, Map.get(input, :timestamp) || DateTime.utc_now())
    end)
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
        project(session)

      _ ->
        Profile.error("memory.history", "Expected a Jido.Session value")
    end
  end

  def read(_, _), do: Profile.error("memory.history", "Expected initialized Agent state")

  @doc false
  def project(value) do
    with {:ok, selected} <- Conversation.select(value),
         {:ok, messages} <- Conversation.messages(selected) do
      {:ok,
       Enum.map(Enum.zip(selected.entries, messages), fn {entry, message} ->
         [value] = entries([message])
         %{value | refs: entry.refs, timestamp: DateTime.from_unix!(entry.at, :millisecond)}
       end)}
    end
  end

  # A complete exchange has one result for every announced call. A pending
  # after-model pause is the only supported position with an open exchange.
  @doc false
  defdelegate open_tool_calls(messages), to: Jido.AI.Conversation

  def messages(entries) do
    with {:ok, context} <- normalize_messages(entries), do: {:ok, context.messages}
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

  def start(state, profile, record, source) do
    with {:ok, _} <- read(state, profile),
         do: {:ok, append(state, profile, query(record.query, refs(record, source)))}
  end

  def append(state, %{memory: %{history: nil}}, _), do: state

  def append(state, profile, entries) do
    session = Map.get(state, profile.memory.history) || Jido.Session.new()
    ref = Jido.AI.Conversation.Control.active_ref(state, profile.id)

    Map.put(state, profile.memory.history, append_entries(session, entries, %{context_ref: ref}))
  end

  @doc false
  def append_entries(value, entries, extra_refs \\ %{}) do
    Enum.reduce(entries, value, fn entry, value ->
      {:ok, messages} = messages([entry])
      refs = Map.merge(Map.get(entry, :refs) || %{}, extra_refs)
      {:ok, [canonical]} = Conversation.entries(messages, refs)

      canonical =
        case entry[:timestamp] do
          %DateTime{} = timestamp -> %{canonical | at: DateTime.to_unix(timestamp, :millisecond)}
          _ -> canonical
        end

      case value do
        %Jido.Session{} -> Jido.Session.append(value, canonical)
        %Jido.Thread{} -> Jido.Thread.append(value, canonical)
      end
    end)
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
