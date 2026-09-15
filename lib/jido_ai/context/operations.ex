defmodule Jido.AI.Context.Operations do
  @moduledoc "Portable context lanes, deferred operations, and their Agent-owned sessions."
  alias Jido.AI.{Configuration, Context, Conversation, History, Profile}
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
    with {:ok, context} <-
           replacement_context(field(operation, :result_context) || field(operation, :context)),
         true <- is_nil(context.system_prompt) or is_binary(context.system_prompt),
         {:ok, entries} <- History.prepare_entries(context.entries) do
      result =
        Context.new(id: context.id, system_prompt: context.system_prompt)
        |> Context.append_messages(entries)

      {:ok, result_thread(result)}
    end
  end

  defp normalize_result(_, _, _, _), do: :error

  defp normalize_enum(value, values),
    do: Enum.find(values, &(value == &1 or value == Atom.to_string(&1)))

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp apply_operation(state, profile, value, operation) do
    current = context(state, profile)
    session = state[profile.memory.history] || Session.new()

    result =
      case operation.operation.type do
        :replace ->
          compact(current, result_view(operation.operation.result_context), operation.operation.reason)

        :switch ->
          project(
            session.thread,
            operation.context_ref,
            Context.new(system_prompt: profile.instructions)
          )
      end

    operation =
      if operation.operation.type == :replace,
        do: put_in(operation.operation.result_context, result_thread(result)),
        else: operation

    session =
      Session.append(session, %{
        kind: :ai_context_operation,
        payload: encode_operation(operation),
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

    prompt =
      if is_binary(result.system_prompt),
        do: [
          %Configuration.Change{
            profile_id: profile.id,
            operation: :prompt,
            value: result.system_prompt
          }
        ],
        else: []

    {:ok, candidate, [%Change{profile_id: profile.id, value: value} | prompt]}
  end

  @doc false
  def project_entries(session, profile) do
    ref =
      session.thread.entries
      |> Enum.filter(&(&1.kind == :ai_context_operation))
      |> List.last()
      |> case do
        nil -> "default"
        entry -> field(entry.payload, :context_ref)
      end

    session.thread
    |> project(ref, Context.new(system_prompt: profile.instructions))
    |> Map.fetch!(:entries)
    |> entry_maps()
  end

  defp context(state, profile) do
    {:ok, entries} = History.read(state, profile)

    Context.new(id: "ai:#{profile.id}", system_prompt: profile.instructions)
    |> Context.append_messages(entries)
  end

  defp project(thread, ref, fallback) do
    Enum.reduce(Thread.to_list(thread), fallback, fn entry, context ->
      if (field(entry.refs, :context_ref) || field(entry.payload, :context_ref) || "default") == ref do
        case entry.kind do
          :ai_context_operation ->
            {:ok, operation} = operation(entry)

            if operation.operation.type == :replace,
              do: result_view(operation.operation.result_context),
              else: context

          :ai_message ->
            {:ok, message} = Conversation.message(entry)
            Context.append_messages(context, [message_fields(message, entry)])

          _ ->
            context
        end
      else
        context
      end
    end)
  end

  defp entry_maps(entries),
    do:
      Enum.map(Enum.reverse(entries), fn
        %Context.Entry{} = entry -> Map.from_struct(entry)
        entry -> entry
      end)

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

            if calls == [], do: [], else: [Map.put(entry, :tool_calls, calls)]

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
              else: [Map.put(entry, :tool_calls, calls)]

          true ->
            [entry]
        end
      end)

    %{replacement | entries: entries ++ kept}
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
        is_nil(name) or tool_name(call) == name,
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
      length(ids) == length(Enum.uniq(ids)) and (is_nil(pending) or valid_operation?(pending))
  end

  defp valid_value?(_), do: false

  defp valid_operation?(%{op_id: id, context_ref: ref, operation: operation})
       when is_map(operation) do
    nonempty?(id) and nonempty?(ref) and operation[:type] in [:replace, :switch] and
      operation[:reason] in [:manual, :restore, :compaction, :system] and
      (is_nil(operation[:base_seq]) or is_integer(operation[:base_seq])) and
      is_map(operation[:meta]) and
      case operation.type do
        :replace -> match?({:ok, _}, Thread.validate(operation[:result_context]))
        :switch -> is_nil(operation[:result_context])
      end
  end

  defp valid_operation?(_), do: false

  @doc "Decodes the portable payload of a committed context operation."
  def operation(%Thread.Entry{kind: :ai_context_operation, payload: %{"version" => 1} = payload}) do
    raw = payload["operation"]
    type = normalize_enum(raw["type"], [:replace, :switch])

    result =
      if type == :replace do
        {:ok, thread} = Thread.decode(raw["result_context"])
        thread
      end

    value = %{
      op_id: payload["op_id"],
      context_ref: payload["context_ref"],
      operation: %{
        type: type,
        reason: normalize_enum(raw["reason"], [:manual, :restore, :compaction, :system]),
        result_context: result,
        base_seq: raw["base_seq"],
        meta: raw["meta"]
      }
    }

    if valid_operation?(value), do: {:ok, value}, else: {:error, :invalid_context_operation}
  rescue
    _ -> {:error, :invalid_context_operation}
  end

  def operation(_), do: {:error, :invalid_context_operation}

  defp encode_operation(value) do
    operation = value.operation

    %{
      "version" => 1,
      "op_id" => value.op_id,
      "context_ref" => value.context_ref,
      "operation" => %{
        "type" => Atom.to_string(operation.type),
        "reason" => Atom.to_string(operation.reason),
        "result_context" => if(operation.result_context, do: Thread.encode(operation.result_context)),
        "base_seq" => operation.base_seq,
        "meta" => operation.meta
      }
    }
  end

  defp replacement_context(%Session{thread: thread}), do: replacement_context(thread)
  defp replacement_context(%Thread{} = thread), do: {:ok, result_view(thread)}
  defp replacement_context(value), do: Context.coerce(value)

  defp result_thread(context) do
    thread = Thread.new(id: context.id, metadata: %{system_prompt: context.system_prompt})

    Enum.reduce(entry_maps(context.entries), thread, fn entry, thread ->
      {:ok, messages} = History.messages([entry])
      {:ok, [canonical]} = Conversation.entries(messages, entry.refs || %{})

      canonical =
        case entry[:timestamp] do
          %DateTime{} = timestamp -> %{canonical | at: DateTime.to_unix(timestamp, :millisecond)}
          _ -> canonical
        end

      Thread.append(thread, canonical)
    end)
  end

  defp result_view(%Thread{} = thread) do
    messages =
      Enum.flat_map(thread.entries, fn entry ->
        if entry.kind in [:ai_message, "ai_message"] do
          {:ok, message} = Conversation.message(entry)
          [message_fields(message, entry)]
        else
          []
        end
      end)

    Context.new(id: thread.id, system_prompt: field(thread.metadata, :system_prompt))
    |> Context.append_messages(messages)
  end

  defp message_fields(message, entry) do
    message
    |> Map.from_struct()
    |> Map.put(:refs, entry.refs)
    |> Map.put(:timestamp, DateTime.from_unix!(entry.at, :millisecond))
  end

  defp nonempty?(value), do: is_binary(value) and value != ""
end
