defmodule Jido.AI.Thread.Projection do
  @moduledoc """
  AI message projection for canonical `Jido.Session` and `Jido.Thread` values.

  AI messages use `:ai_message` entries with a versioned, JSON-safe payload.
  Other entry kinds belong to applications and are not sent to the model.
  This module holds no conversation state. References stay on Thread entries,
  outside provider messages. Binary content is stored as explicit base64 data.
  """
  @doc false
  def project(value) do
    with {:ok, selected} <- select(value),
         {:ok, messages} <- messages(selected) do
      {:ok,
       Enum.map(Enum.zip(selected.entries, messages), fn {entry, message} ->
         [value] = Jido.AI.Model.Messages.entries([message])
         %{value | refs: entry.refs, timestamp: DateTime.from_unix!(entry.at, :millisecond)}
       end)}
    end
  end

  @doc false
  def append_entries(value, entries, extra_refs \\ %{}, policy \\ nil) do
    Enum.reduce(entries, value, fn entry, value ->
      {:ok, messages} = Jido.AI.Model.Messages.messages([entry])
      refs = Map.merge(Map.get(entry, :refs) || %{}, extra_refs)

      {messages, omitted?} =
        if is_map(policy) do
          pairs = Enum.map(messages, &Jido.AI.Observe.Content.message(&1, policy))
          {Enum.map(pairs, &elem(&1, 0)), Enum.any?(pairs, &elem(&1, 1))}
        else
          {messages, false}
        end

      refs = if omitted?, do: Map.put(refs, :content_omitted, true), else: refs
      {:ok, [canonical]} = entries(messages, refs)

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

  alias Jido.{Session, Thread}
  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart

  @roles [:user, :assistant, :system, :tool]
  @parts [:text, :image_url, :video_url, :image, :file, :thinking]

  @doc "Schema for an Agent conversation field. Nil means no session has started."
  def schema, do: Session.schema() |> Zoi.nullable() |> Zoi.default(nil)

  @doc false
  def before_request(%Session{} = session, id) do
    entries =
      session.thread.entries |> Enum.reverse() |> Enum.drop_while(&(&1.refs[:request_id] == id)) |> Enum.reverse()

    count = length(entries)
    thread = %{session.thread | entries: entries, rev: count, stats: %{entry_count: count}}
    %{session | thread: thread, rev: session.rev - (session.thread.rev - count)}
  end

  def before_request(nil, _), do: nil

  @doc "Builds canonical entries from ReqLLM-compatible messages."
  def entries(messages, refs \\ %{}) do
    with {:ok, context} <- ReqLLM.Context.normalize(messages) do
      safely(fn ->
        Enum.map(context.messages, fn message ->
          Thread.Entry.new(kind: :ai_message, payload: encode(message), refs: refs)
        end)
      end)
    end
  end

  @doc "Appends model messages to a Session or Thread without another store."
  def append(value, messages, refs \\ %{}) do
    with {:ok, entries} <- entries(messages, refs) do
      safely(fn ->
        case value do
          %Session{} -> Session.append(value, entries)
          %Thread{} -> Thread.append(value, entries)
        end
      end)
    end
  end

  @doc "Projects AI entries in order. Application entry kinds are ignored."
  def messages(%Session{thread: thread}), do: messages(thread)

  def messages(%Thread{} = thread) do
    with {:ok, thread} <- select(thread) do
      evidence_messages(thread)
    end
  end

  @doc false
  def evidence_messages(%Session{thread: thread}), do: evidence_messages(thread)

  def evidence_messages(%Thread{} = thread) do
    safely(fn ->
      thread.entries
      |> Enum.filter(&(&1.kind in [:ai_message, "ai_message"]))
      |> Enum.map(&decode(&1.payload))
    end)
  end

  @doc "Selects the active conversation from the append-only log, or a named lane."
  def select(value, ref \\ nil, opts \\ [])
  def select(%Session{thread: thread}, ref, opts), do: select(thread, ref, opts)

  def select(%Thread{} = thread, ref, opts) do
    with {:ok, _} <- Thread.validate(thread) do
      safely(fn ->
        operations = Enum.filter(thread.entries, &(&1.kind in [:ai_context_operation, "ai_context_operation"]))

        ref =
          ref ||
            case List.last(operations) do
              nil -> nil
              entry -> operation!(entry).context_ref
            end

        settled =
          thread.entries
          |> Enum.filter(
            &(&1.kind in [:ai_request_settled, "ai_request_settled"] and
                field(&1.payload, :status) in [:completed, "completed"])
          )
          |> Enum.map(&{field(&1.refs, :request_id), field(&1.refs, :run_id)})
          |> MapSet.new()

        {entries, metadata} =
          Enum.reduce(thread.entries, {[], thread.metadata}, fn entry, acc ->
            lane = field(entry.refs, :context_ref) || field(entry.payload, :context_ref) || "default"

            case {is_nil(ref) or lane == ref, entry.kind} do
              {true, kind} when kind in [:ai_context_operation, "ai_context_operation"] ->
                case operation!(entry).operation do
                  %{type: :replace, result_context: snapshot} ->
                    {:ok, selected} = select(snapshot, nil, opts)
                    entries = selected.entries
                    {Enum.reverse(entries), snapshot.metadata}

                  %{type: :switch} ->
                    acc
                end

              {true, kind} when kind in [:ai_message, "ai_message"] ->
                {entries, metadata} = acc

                if field(entry.refs, :conversation) in [:pending, "pending"] and
                     not MapSet.member?(settled, {field(entry.refs, :request_id), field(entry.refs, :run_id)}) do
                  acc
                else
                  entry = %{entry | refs: Map.drop(entry.refs, [:conversation, "conversation"])}
                  {[entry | entries], metadata}
                end

              _ ->
                acc
            end
          end)

        entries = Enum.reverse(entries)
        entries = if Keyword.get(opts, :complete_exchanges, true), do: complete_exchanges(entries), else: entries
        Thread.new(id: thread.id, metadata: metadata) |> Thread.append(entries)
      end)
    end
  end

  def select(_, _, _), do: {:error, :invalid_conversation}

  # Keep an exchange only when all call IDs have matching results. Never invent
  # a tool response for an incomplete exchange in the retained evidence.
  defp complete_exchanges(entries) do
    {completed, _pending, _open} =
      Enum.reduce(entries, {[], [], %{}}, fn entry, {completed, pending, open} ->
        message = decode(entry.payload)

        cond do
          message.role == :assistant and (message.tool_calls || []) != [] ->
            calls = Enum.map(message.tool_calls, &ReqLLM.ToolCall.to_map/1)
            ids = Enum.map(calls, & &1.id)

            if length(ids) == length(Enum.uniq(ids)),
              do: {completed, [entry], Map.new(calls, &{&1.id, &1.name})},
              else: {completed, [], %{}}

          message.role == :tool and Map.has_key?(open, message.tool_call_id) and
              message.name in [nil, open[message.tool_call_id]] ->
            open = Map.delete(open, message.tool_call_id)
            pending = [entry | pending]
            if map_size(open) == 0, do: {pending ++ completed, [], open}, else: {completed, pending, open}

          message.role == :tool ->
            {completed, pending, open}

          true ->
            {[entry | completed], [], %{}}
        end
      end)

    Enum.reverse(completed)
  end

  defp operation!(entry) do
    {:ok, operation} = Jido.AI.Thread.Operation.decode(entry)
    operation
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  @doc "Projects one canonical AI entry. References remain outside the message."
  def message(%Thread.Entry{kind: kind, payload: payload}) when kind in [:ai_message, "ai_message"],
    do: safely(fn -> decode(payload) end)

  def message(_), do: {:error, :invalid_conversation}

  @doc "Validates exchange ordering and returns pending calls for checkpoint use."
  def open_tool_calls(messages) do
    Enum.reduce_while(messages, {:ok, %{}}, fn message, {:ok, open} ->
      case advance(message, open) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp advance(%{role: :tool, tool_call_id: id, name: name}, open) do
    case open[id] do
      %{name: expected} when name in [nil, expected] -> {:ok, Map.delete(open, id)}
      _ -> {:error, :invalid_tool_history}
    end
  end

  defp advance(%{role: :assistant} = message, open) when map_size(open) == 0 do
    calls = Enum.map(message.tool_calls || [], &ReqLLM.ToolCall.to_map/1)
    ids = Enum.map(calls, & &1.id)

    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and ids == Enum.uniq(ids),
      do: {:ok, Map.new(calls, &{&1.id, &1})},
      else: {:error, :invalid_tool_history}
  end

  defp advance(_, open) when map_size(open) == 0, do: {:ok, open}
  defp advance(_, _), do: {:error, :invalid_tool_history}

  defp encode(%Message{} = message) do
    %{
      "version" => 1,
      "role" => Atom.to_string(message.role),
      "content" => Enum.map(message.content, &encode_part/1),
      "name" => message.name,
      "tool_call_id" => message.tool_call_id,
      "tool_calls" => Enum.map(message.tool_calls || [], &ReqLLM.ToolCall.to_map/1),
      "metadata" => Map.drop(message.metadata, [:jido_ai_refs, "jido_ai_refs"]),
      "reasoning_details" => Enum.map(message.reasoning_details || [], &encode_reasoning/1)
    }
    |> json()
  end

  defp encode_part(%ContentPart{} = part) do
    data = Map.from_struct(part)

    if is_binary(part.data),
      do: data |> Map.put(:data, Base.encode64(part.data)) |> Map.put(:data_encoding, "base64"),
      else: data
  end

  defp decode(%{"version" => 1} = payload) do
    true = Map.keys(payload) -- ~w(version role content name tool_call_id tool_calls metadata reasoning_details) == []
    role = enum!(payload["role"], @roles)

    calls =
      Enum.map(payload["tool_calls"] || [], fn call ->
        true = is_binary(call["id"]) and call["id"] != "" and is_binary(call["name"]) and call["name"] != ""
        true = is_map(call["arguments"])

        ReqLLM.ToolCall.new(call["id"], call["name"], Jason.encode!(call["arguments"]))
        |> ReqLLM.ToolCall.put_metadata(call["metadata"] || %{})
      end)

    message = %Message{
      role: role,
      content: Enum.map(payload["content"], &decode_part/1),
      name: payload["name"],
      tool_call_id: payload["tool_call_id"],
      tool_calls: if(calls == [], do: nil, else: calls),
      metadata: payload["metadata"] || %{},
      reasoning_details: decode_reasoning(payload["reasoning_details"])
    }

    {:ok, _} = Zoi.parse(Message.schema(), message)
    true = role != :tool or (is_binary(message.tool_call_id) and message.tool_call_id != "")
    message
  end

  defp decode_part(part) do
    fields = Map.keys(Map.from_struct(%ContentPart{type: :text}))
    true = Map.keys(part) -- ["data_encoding" | Enum.map(fields, &Atom.to_string/1)] == []
    true = part["data_encoding"] in [nil, "base64"]
    attrs = Map.new(fields, &{&1, part[Atom.to_string(&1)]})
    attrs = %{attrs | type: enum!(part["type"], @parts), metadata: part["metadata"] || %{}}
    attrs = if part["data_encoding"] == "base64", do: %{attrs | data: Base.decode64!(part["data"])}, else: attrs
    value = struct!(ContentPart, attrs)
    {:ok, _} = Zoi.parse(ContentPart.schema(), value)
    value
  end

  defp encode_reasoning(%Message.ReasoningDetails{} = value),
    do: %{"type" => "normalized", "value" => Map.from_struct(value)}

  defp encode_reasoning(value) when is_map(value), do: %{"type" => "provider", "value" => value}

  defp decode_reasoning(value) when value in [nil, []], do: nil

  defp decode_reasoning(values) do
    Enum.map(values, fn
      %{"type" => "provider", "value" => value} when is_map(value) ->
        value

      %{"type" => "normalized", "value" => value} ->
        fields = Map.keys(Map.from_struct(%Message.ReasoningDetails{}))
        attrs = Map.new(fields, &{&1, value[Atom.to_string(&1)]})
        provider = if is_binary(attrs.provider), do: String.to_existing_atom(attrs.provider), else: nil
        struct!(Message.ReasoningDetails, %{attrs | provider: provider})
    end)
  end

  defp enum!(value, allowed) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) || raise ArgumentError, "invalid message enum"
  end

  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp safely(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_conversation}
  end
end
