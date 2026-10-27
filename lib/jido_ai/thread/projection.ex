defmodule Jido.AI.Thread.Projection do
  @moduledoc """
  Projects the canonical `Jido.Session` Thread into portable model messages.

  Only eligible `:ai_message` entries enter the model context. Runtime
  observations, review records, and request outcomes stay in the Thread but
  outside prompts. Messages from failed or blocked requests stay available for
  inspection but do not enter later model requests. Incomplete tool exchanges
  are also excluded.
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
  def project(%Session{} = session, config) when is_map(config) do
    with {:ok, explanation} <- explain(session, config) do
      {:ok,
       Map.take(explanation, [
         :messages,
         :available_messages,
         :included_messages,
         :dropped_messages,
         :first_seq,
         :last_seq
       ])}
    end
  end

  def project(_session, _config), do: {:error, :invalid_context}

  @doc "Projects a Thread and reports why each model message was included or excluded."
  @spec explain(Session.t(), map()) :: {:ok, map()} | {:error, :invalid_context}
  def explain(%Session{thread: thread}, config) when is_map(config) do
    with {:ok, _thread} <- Thread.validate(thread) do
      outcomes = request_outcomes(thread.entries)
      message_entries = Enum.filter(thread.entries, &message_entry?/1)
      eligible_entries = Enum.filter(message_entries, &context_entry?(&1, outcomes))

      eligible_entries
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
          completed_ids = entry_ids(completed)
          selected_ids = entry_ids(selected)

          {:ok,
           %{
             messages: Enum.map(selected, &elem(&1, 1)),
             entries: Enum.map(selected, &portable_pair/1),
             decisions:
               projection_decisions(
                 message_entries,
                 eligible_entries,
                 completed_ids,
                 selected_ids,
                 outcomes
               ),
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

  def explain(_session, _config), do: {:error, :invalid_context}

  @doc "Returns the final included Thread sequence for one projection."
  @spec breakpoint(Session.t()) :: non_neg_integer() | nil
  def breakpoint(%Session{thread: thread}) do
    thread.entries
    |> context_entries()
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

  defp context_entries(entries) do
    outcomes = request_outcomes(entries)

    Enum.filter(entries, fn entry ->
      message_entry?(entry) and context_entry?(entry, outcomes)
    end)
  end

  defp message_entry?(entry), do: entry.kind in [:ai_message, "ai_message"]

  defp entry_ids(pairs), do: MapSet.new(pairs, fn {entry, _message} -> entry.id end)

  defp portable_pair({entry, message}) do
    %{
      id: entry.id,
      seq: entry.seq,
      at: entry.at,
      refs: entry.refs,
      message: message
    }
  end

  defp projection_decisions(entries, eligible, completed_ids, selected_ids, outcomes) do
    eligible_ids = MapSet.new(eligible, & &1.id)

    Enum.map(entries, fn entry ->
      cond do
        not MapSet.member?(eligible_ids, entry.id) ->
          decision(entry, :excluded, request_outcome_reason(entry, outcomes))

        not MapSet.member?(completed_ids, entry.id) ->
          decision(entry, :excluded, :incomplete_tool_exchange)

        not MapSet.member?(selected_ids, entry.id) ->
          decision(entry, :excluded, :outside_context_window)

        true ->
          decision(entry, :included, :projected)
      end
    end)
  end

  defp decision(entry, state, reason) do
    %{entry_id: entry.id, seq: entry.seq, state: state, reason: reason, refs: entry.refs}
  end

  defp request_outcome_reason(entry, outcomes) do
    case field(entry.refs, :run_id) do
      run_id when is_binary(run_id) and run_id != "" ->
        if Map.get(outcomes, run_id) == false, do: :request_not_completed, else: :not_eligible

      _other ->
        :not_eligible
    end
  end

  defp request_outcomes(entries) do
    Enum.reduce(entries, %{}, fn entry, outcomes ->
      if entry.kind in [:ai_request_outcome, "ai_request_outcome"] do
        case field(entry.refs, :run_id) do
          run_id when is_binary(run_id) and run_id != "" ->
            Map.put(outcomes, run_id, field(entry.payload, :status) in [:completed, "completed"])

          _other ->
            outcomes
        end
      else
        outcomes
      end
    end)
  end

  defp context_entry?(entry, outcomes) do
    case field(entry.refs, :run_id) do
      run_id when is_binary(run_id) and run_id != "" -> Map.get(outcomes, run_id, true)
      _other -> true
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
         content when is_binary(content) or is_list(content) <- field(message, :content) || "",
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
         content when is_binary(content) or is_list(content) <- payload["content"] || "",
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
