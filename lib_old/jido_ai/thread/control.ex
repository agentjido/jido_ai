defmodule Jido.AI.Thread.Control do
  @moduledoc false
  alias Jido.AI.Configuration
  alias Jido.AI.Profile
  alias Jido.AI.Thread.Projection
  alias Jido.{Session, Thread}
  alias __MODULE__.Change
  @key :jido_ai_contexts
  @signal_type "jido.ai.context.modify"

  def key, do: @key
  def type, do: @signal_type

  def routes do
    [{@signal_type, __MODULE__.Apply}]
  end

  def active_ref(state, id), do: get_in(state, [@key, id, :active_context_ref]) || "default"

  @doc false
  def session_id(state, profile, _agent_id), do: state[profile.memory.history].id

  def live(server, operation, opts \\ []) do
    signal =
      Jido.Signal.new!(
        @signal_type,
        %{
          profile_id: opts[:profile],
          op_id: opts[:op_id],
          context_ref: opts[:context_ref],
          operation: operation
        },
        source: "/jido/ai/context"
      )

    Jido.AgentServer.call(server, signal, timeout: Keyword.get(opts, :timeout, 5_000))
  end

  def modify(params, context) do
    agent = context.jido_ai_agent

    with {:ok, opts} <- Configuration.options(agent),
         {:ok, id} <- Configuration.select_id(opts, field(params, :profile_id)),
         {:ok, profile} <- Configuration.profile(agent, id),
         true <- profile.memory.history != nil,
         value = value(context.agent_state, profile, agent.id),
         {:ok, operation} <- normalize(params, value, profile, agent, context.signal.id) do
      cond do
        operation.op_id in value.applied_context_ops ->
          {:ok, context.agent_state, []}

        active?(context.agent_state, id) ->
          value = %{value | pending_context_op: operation}
          {:ok, context.agent_state, [%Change{profile_id: id, value: value}]}

        true ->
          apply_operation(context.agent_state, profile, value, operation)
      end
    else
      _ ->
        Profile.error(
          "context.operation",
          "Expected a valid portable context operation and a profile with history"
        )
    end
  end

  def finish(candidate, record, context) do
    profile = context.jido_ai_profiles[record.profile_id]

    case get_in(context.agent_state, [@key, record.profile_id]) do
      %{pending_context_op: %{op_id: _} = operation} = value ->
        apply_operation(candidate, profile, value, operation)

      _ ->
        {:ok, candidate, []}
    end
  end

  defp active?(state, id),
    do:
      Enum.any?(Map.get(state, :requests, %{}), fn {_, r} ->
        r.status == :pending and r.profile_id == id
      end)

  defp value(state, profile, agent_id) do
    case get_in(state, [@key, profile.id]) do
      nil -> new_value(agent_id, profile.id)
      value -> value
    end
  end

  defp new_value(_agent_id, _profile_id) do
    %{
      active_context_ref: "default",
      pending_context_op: nil,
      applied_context_ops: []
    }
  end

  defp normalize(params, value, profile, agent, signal_id) do
    operation = field(params, :operation)
    type = normalize_enum(field(operation, :type), [:replace, :switch])

    reason =
      normalize_enum(field(operation, :reason) || :manual, [
        :manual,
        :restore,
        :compaction,
        :system
      ])

    ref =
      field(params, :context_ref) || field(operation, :context_ref) || value.active_context_ref

    id =
      field(params, :op_id) || field(operation, :op_id) || field(params, :signal_id) || signal_id

    with true <-
           type != nil and reason != nil and is_binary(ref) and ref != "" and is_binary(id) and
             id != "",
         {:ok, result} <- normalize_result(type, operation, profile, agent),
         data = %{
           op_id: id,
           context_ref: ref,
           operation: %{
             type: type,
             reason: reason,
             result_context: result,
             base_seq: if(is_integer(field(operation, :base_seq)), do: field(operation, :base_seq)),
             meta: if(is_map(field(operation, :meta)), do: field(operation, :meta), else: %{})
           }
         },
         :ok <- Jido.Action.validate_static_data(data),
         do: {:ok, data}
  end

  defp normalize_result(:switch, _, _, _), do: {:ok, nil}

  defp normalize_result(:replace, operation, _profile, _agent) do
    with {:ok, thread} <-
           replacement_context(field(operation, :result_context)),
         prompt = field(thread.metadata, :system_prompt),
         true <- is_nil(prompt) or is_binary(prompt),
         {:ok, _} <- Projection.messages(thread) do
      {:ok, thread}
    end
  end

  defp normalize_result(_, _, _, _), do: :error

  defp normalize_enum(value, values),
    do: Enum.find(values, &(value == &1 or value == Atom.to_string(&1)))

  defp field(%Thread.Entry{refs: refs}, :refs), do: refs
  defp field(%Thread.Entry{payload: payload}, key), do: field(payload, key)
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp apply_operation(state, profile, value, operation) do
    session = state[profile.memory.history] || Session.new()
    {:ok, current} = Projection.select(session)

    result =
      case operation.operation.type do
        :replace ->
          compact(current, operation.operation.result_context, operation.operation.reason)

        :switch ->
          project(
            session.thread,
            operation.context_ref,
            profile.instructions
          )
      end

    operation =
      if operation.operation.type == :replace,
        do: put_in(operation.operation.result_context, result),
        else: operation

    session =
      Session.append(session, %{
        kind: :ai_context_operation,
        payload: Jido.AI.Thread.Operation.encode(operation),
        refs: %{op_id: operation.op_id, context_ref: operation.context_ref}
      })

    value = %{
      value
      | active_context_ref: operation.context_ref,
        pending_context_op: nil,
        applied_context_ops:
          Enum.take(
            [operation.op_id | Enum.reject(value.applied_context_ops, &(&1 == operation.op_id))],
            128
          )
    }

    candidate = Map.put(state, profile.memory.history, session)

    saved_prompt = field(result.metadata, :system_prompt)

    prompt =
      if is_binary(saved_prompt),
        do: [
          %Configuration.Change{
            profile_id: profile.id,
            operation: :prompt,
            value: saved_prompt
          }
        ],
        else: []

    {:ok, candidate, [%Change{profile_id: profile.id, value: value} | prompt]}
  end

  defp project(thread, ref, fallback) do
    {:ok, selected} = Projection.select(thread, ref)
    metadata = selected.metadata

    metadata =
      if Map.has_key?(metadata, :system_prompt) or Map.has_key?(metadata, "system_prompt"),
        do: metadata,
        else: Map.put(metadata, :system_prompt, fallback)

    %{selected | metadata: metadata}
  end

  defp put_calls(entry, calls), do: %{entry | payload: Map.put(entry.payload, "tool_calls", calls)}

  defp compact(current, replacement, :compaction) do
    assistant_ids = tool_ids(current.entries, "load_skill")

    durable_ids =
      current.entries
      |> Enum.filter(&durable?/1)
      |> Enum.map(&field(&1, :tool_call_id))
      |> MapSet.new()
      |> MapSet.intersection(assistant_ids)

    kept =
      Enum.flat_map(current.entries, fn entry ->
        cond do
          field(entry, :role) in [:tool, "tool"] and
              MapSet.member?(durable_ids, field(entry, :tool_call_id)) ->
            [entry]

          field(entry, :role) in [:assistant, "assistant"] ->
            calls =
              Enum.filter(List.wrap(field(entry, :tool_calls)), fn call ->
                id = field(call, :id)
                MapSet.member?(durable_ids, id) and tool_name(call) == "load_skill"
              end)

            if calls == [], do: [], else: [put_calls(entry, calls)]

          true ->
            []
        end
      end)

    entries =
      Enum.flat_map(replacement.entries, fn entry ->
        cond do
          field(entry, :role) in [:tool, "tool"] and
              MapSet.member?(durable_ids, field(entry, :tool_call_id)) ->
            []

          field(entry, :role) in [:assistant, "assistant"] ->
            original = List.wrap(field(entry, :tool_calls))
            calls = Enum.reject(original, &MapSet.member?(durable_ids, field(&1, :id)))

            if original != [] and calls == [] and field(entry, :content) in [nil, "", []],
              do: [],
              else: [put_calls(entry, calls)]

          true ->
            [entry]
        end
      end)

    Thread.new(id: replacement.id, metadata: replacement.metadata) |> Thread.append(kept ++ entries)
  end

  defp compact(_, replacement, _), do: replacement

  defp durable?(entry) do
    refs = field(entry, :refs)

    field(entry, :role) in [:tool, "tool"] and field(entry, :name) == "load_skill" and
      is_binary(field(entry, :tool_call_id)) and field(refs, :durable) == true and
      field(refs, :kind) in [:skill_activation, "skill_activation"] and
      is_binary(field(refs, :skill_name))
  end

  defp tool_ids(entries, name) do
    for entry <- entries,
        field(entry, :role) in [:assistant, "assistant"],
        call <- List.wrap(field(entry, :tool_calls)),
        id = field(call, :id),
        is_binary(id),
        tool_name(call) == name,
        into: MapSet.new(),
        do: id
  end

  defp tool_name(call), do: field(call, :name) || field(field(call, :function), :name)

  def validate_state(values, profiles, _) when is_map(values) do
    valid =
      Enum.all?(values, fn {id, value} ->
        Map.has_key?(profiles, id) and valid_value?(value)
      end)

    if valid and Jido.Action.validate_static_data(values) == :ok,
      do: :ok,
      else: {:error, "Expected portable context lanes for declared profiles"}
  rescue
    _ -> {:error, "Invalid saved context data"}
  end

  def validate_state(_, _, _), do: {:error, "Expected context lanes"}

  defp valid_value?(
         %{
           active_context_ref: ref,
           pending_context_op: pending,
           applied_context_ops: ids
         } = value
       ) do
    Map.keys(value) -- [:active_context_ref, :pending_context_op, :applied_context_ops] ==
      [] and
      nonempty?(ref) and is_list(ids) and length(ids) <= 128 and Enum.all?(ids, &nonempty?/1) and
      length(ids) == length(Enum.uniq(ids)) and (is_nil(pending) or Jido.AI.Thread.Operation.valid?(pending))
  end

  defp valid_value?(_), do: false

  defp replacement_context(%Session{} = session) do
    with {:ok, _} <- Session.validate(session), do: Projection.select(session)
  end

  defp replacement_context(%Thread{} = thread), do: Projection.select(thread)

  defp replacement_context(value) when is_map(value) do
    with {:ok, thread} <- Thread.decode(value), do: Projection.select(thread)
  end

  defp replacement_context(_), do: {:error, :invalid_context}

  defp nonempty?(value), do: is_binary(value) and value != ""
end
