defmodule Jido.AI.Thread.Projection do
  @moduledoc """
  Projects the canonical `Jido.Session` Thread into portable model messages.

  Only `:ai_message` entries enter the model context. Runtime observations,
  review records, and request outcomes stay in the Thread but outside prompts.
  Incomplete tool exchanges are also excluded.
  """

  alias Jido.{Session, Thread}

  @roles [:system, :user, :assistant, :tool]

  @doc "Returns the canonical Agent-state schema for a nullable Session."
  @spec schema() :: Zoi.schema()
  def schema, do: Session.state_schema() |> Zoi.nullable() |> Zoi.default(nil)

  @doc "Appends one portable model message to a Session."
  @spec append(Session.t(), map(), map(), integer()) :: {:ok, Session.t()} | {:error, term()}
  def append(%Session{} = session, message, refs \\ %{}, at \\ System.system_time(:millisecond)) do
    with {:ok, payload} <- encode_message(message) do
      entry = Thread.Entry.new(kind: :ai_message, payload: payload, refs: refs, at: at)
      {:ok, Session.append(session, entry)}
    end
  rescue
    _error -> {:error, :invalid_context}
  end

  @doc "Appends one non-message observation to a Session."
  @spec observe(Session.t(), atom(), map(), map(), integer()) :: Session.t()
  def observe(%Session{} = session, kind, payload, refs \\ %{}, at \\ System.system_time(:millisecond))
      when is_atom(kind) and is_map(payload) and is_map(refs) and is_integer(at) do
    Session.append(session, Thread.Entry.new(kind: kind, payload: json(payload), refs: refs, at: at))
  end

  @doc "Projects complete model exchanges from a Session."
  @spec messages(Session.t()) :: {:ok, [map()]} | {:error, :invalid_context}
  def messages(%Session{} = session) do
    with {:ok, projection} <- project(session, %{}) do
      {:ok, projection.messages}
    end
  end

  @doc "Projects a bounded set of complete conversation turns from a Session."
  @spec project(Session.t(), map()) :: {:ok, map()} | {:error, :invalid_context}
  def project(%Session{thread: thread}, config) when is_map(config) do
    with {:ok, _thread} <- Thread.validate(thread) do
      thread.entries
      |> Enum.filter(&(&1.kind in [:ai_message, "ai_message"]))
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, messages} ->
        case decode_message(entry.payload) do
          {:ok, message} -> {:cont, {:ok, [{entry, message} | messages]}}
          {:error, _reason} -> {:halt, {:error, :invalid_context}}
        end
      end)
      |> case do
        {:ok, pairs} ->
          completed = pairs |> Enum.reverse() |> complete_exchanges()
          selected = select_turns(completed, config)

          {:ok,
           %{
             messages: Enum.map(selected, &elem(&1, 1)),
             available_messages: length(completed),
             included_messages: length(selected),
             dropped_messages: length(completed) - length(selected),
             first_seq: sequence(List.first(selected)),
             last_seq: sequence(List.last(selected))
           }}

        error ->
          error
      end
    else
      _other -> {:error, :invalid_context}
    end
  end

  def project(_session, _config), do: {:error, :invalid_context}

  @doc "Returns the final included Thread sequence for one projection."
  @spec breakpoint(Session.t()) :: non_neg_integer() | nil
  def breakpoint(%Session{thread: thread}) do
    thread.entries
    |> Enum.filter(&(&1.kind in [:ai_message, "ai_message"]))
    |> complete_exchange_entries()
    |> List.last()
    |> case do
      nil -> nil
      entry -> entry.seq
    end
  end

  defp complete_exchange_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, pairs} ->
      case decode_message(entry.payload) do
        {:ok, message} -> {:cont, {:ok, [{entry, message} | pairs]}}
        {:error, _reason} -> {:halt, {:error, :invalid_context}}
      end
    end)
    |> case do
      {:ok, pairs} -> pairs |> Enum.reverse() |> complete_exchanges() |> Enum.map(&elem(&1, 0))
      {:error, _reason} -> []
    end
  end

  # Keep an assistant tool request only when every call has one matching tool result.
  defp complete_exchanges(pairs) do
    {completed, _pending, _open} =
      Enum.reduce(pairs, {[], [], %{}}, fn {entry, message} = pair, {completed, pending, open} ->
        cond do
          message.role == :assistant and message.tool_calls != [] ->
            ids = Enum.map(message.tool_calls, & &1.id)

            if ids == Enum.uniq(ids) and Enum.all?(ids, &(is_binary(&1) and &1 != "")) do
              {completed, [pair], Map.new(message.tool_calls, &{&1.id, &1.name})}
            else
              {completed, [], %{}}
            end

          message.role == :tool and Map.has_key?(open, message.tool_call_id) and
              message.name in [nil, open[message.tool_call_id]] ->
            next_open = Map.delete(open, message.tool_call_id)
            next_pending = pending ++ [{entry, message}]

            if map_size(next_open) == 0,
              do: {completed ++ next_pending, [], next_open},
              else: {completed, next_pending, next_open}

          message.role == :tool ->
            {completed, pending, open}

          true ->
            {completed ++ [pair], [], %{}}
        end
      end)

    completed
  end

  defp select_turns(pairs, config) do
    limits = %{
      max_messages: positive_limit(field(config, :max_messages)),
      max_bytes: positive_limit(field(config, :max_bytes))
    }

    pairs
    |> conversation_turns()
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0, 0}, fn turn, {selected, messages, bytes} ->
      next_messages = messages + length(turn)
      next_bytes = bytes + turn_bytes(turn)

      if selected != [] and exceeds?(next_messages, next_bytes, limits) do
        {:halt, {selected, messages, bytes}}
      else
        {:cont, {[turn | selected], next_messages, next_bytes}}
      end
    end)
    |> elem(0)
    |> Enum.concat()
  end

  defp conversation_turns(pairs) do
    {turns, current} =
      Enum.reduce(pairs, {[], []}, fn {_entry, message} = pair, {turns, current} ->
        if message.role == :user and current != [] do
          {[Enum.reverse(current) | turns], [pair]}
        else
          {turns, [pair | current]}
        end
      end)

    case current do
      [] -> Enum.reverse(turns)
      values -> Enum.reverse([Enum.reverse(values) | turns])
    end
  end

  defp exceeds?(messages, bytes, limits) do
    over?(messages, limits.max_messages) or over?(bytes, limits.max_bytes)
  end

  defp over?(_value, nil), do: false
  defp over?(value, limit), do: value > limit
  defp positive_limit(value) when is_integer(value) and value > 0, do: value
  defp positive_limit(_value), do: nil
  defp turn_bytes(turn), do: turn |> Enum.map(&elem(&1, 1)) |> Jason.encode!() |> byte_size()
  defp sequence(nil), do: nil
  defp sequence({entry, _message}), do: entry.seq

  defp encode_message(message) when is_map(message) do
    with role when role in @roles <- role(field(message, :role)),
         content when is_binary(content) <- field(message, :content) || "",
         {:ok, tool_calls} <- encode_tool_calls(field(message, :tool_calls) || []) do
      {:ok,
       json(%{
         "version" => 1,
         "role" => Atom.to_string(role),
         "content" => content,
         "name" => field(message, :name),
         "tool_call_id" => field(message, :tool_call_id),
         "tool_calls" => tool_calls,
         "output" => field(message, :output),
         "metadata" => field(message, :metadata) || %{}
       })}
    else
      _other -> {:error, :invalid_message}
    end
  rescue
    _error -> {:error, :invalid_message}
  end

  defp decode_message(%{"version" => 1} = payload) do
    with role when role in @roles <- role(payload["role"]),
         content when is_binary(content) <- payload["content"] || "",
         {:ok, tool_calls} <- decode_tool_calls(payload["tool_calls"] || []) do
      {:ok,
       %{
         role: role,
         content: content,
         name: payload["name"],
         tool_call_id: payload["tool_call_id"],
         tool_calls: tool_calls,
         output: payload["output"],
         metadata: payload["metadata"] || %{}
       }}
    else
      _other -> {:error, :invalid_message}
    end
  end

  defp decode_message(_payload), do: {:error, :invalid_message}

  defp encode_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, encoded} ->
      case tool_call(call) do
        {:ok, value} -> {:cont, {:ok, [value | encoded]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp encode_tool_calls(_calls), do: {:error, :invalid_message}

  defp decode_tool_calls(calls), do: encode_tool_calls(calls)

  defp tool_call(call) when is_map(call) do
    id = field(call, :id)
    name = field(call, :name)
    arguments = field(call, :arguments)

    if is_binary(id) and id != "" and is_binary(name) and name != "" and is_map(arguments) do
      {:ok, %{id: id, name: name, arguments: json(arguments)}}
    else
      {:error, :invalid_message}
    end
  end

  defp tool_call(_call), do: {:error, :invalid_message}

  defp role(value) when value in @roles, do: value
  defp role("system"), do: :system
  defp role("user"), do: :user
  defp role("assistant"), do: :assistant
  defp role("tool"), do: :tool
  defp role(_value), do: nil
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()
end
