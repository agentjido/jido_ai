defmodule Jido.AI.Context.Operations.Change do
  @moduledoc false
  defstruct [:profile_id, :value]
end

defmodule Jido.AI.Context.Operations do
  @moduledoc "Portable context lanes, deferred operations and their Thread records."
  alias Jido.AI.{Configuration, Context, History, Profile}
  alias __MODULE__.Change
  @key :jido_ai_contexts
  @signal_type "jido.ai.context.modify"

  def key, do: @key
  def type, do: @signal_type

  def routes do
    [
      {@signal_type, __MODULE__.Apply},
      {"ai.react.context.modify", {__MODULE__.Apply, %{legacy?: true}}}
    ]
  end

  def active_ref(state, id), do: get_in(state, [@key, id, :active_context_ref]) || "default"

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

  def capture(_state, %{memory: %{history: nil}}, _entries, _agent_id, _record), do: []

  def capture(state, profile, entries, agent_id, record) do
    value = value(state, profile, agent_id)
    value = sync(value, state, profile)
    thread = append_messages(value.thread, entries, value.active_context_ref, record)
    [%Change{profile_id: profile.id, value: %{value | thread: thread}}]
  end

  defp active?(state, id),
    do:
      Enum.any?(Map.get(state, :requests, %{}), fn {_, r} ->
        r.status == :pending and r.profile_id == id
      end)

  defp value(state, profile, agent_id) do
    get_in(state, [@key, profile.id]) ||
      %{
        active_context_ref: "default",
        pending_context_op: nil,
        applied_context_ops: [],
        thread: Jido.Thread.new(id: "ai:#{agent_id}:#{profile.id}")
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

  defp normalize_result(:replace, operation, profile, agent) do
    with {:ok, context} <-
           Context.coerce(field(operation, :result_context) || field(operation, :context)),
         true <- is_nil(context.system_prompt) or is_binary(context.system_prompt),
         {:ok, checked} <- History.replace(agent, profile, context.entries) do
      result =
        Context.new(id: context.id, system_prompt: context.system_prompt)
        |> Context.append_messages(checked.state[profile.memory.history])

      {:ok, result}
    end
  end

  defp normalize_result(_, _, _, _), do: :error

  defp normalize_enum(value, values),
    do: Enum.find(values, &(value == &1 or value == Atom.to_string(&1)))

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp apply_operation(state, profile, value, operation) do
    value = sync(value, state, profile)
    current = context(state, profile)

    result =
      case operation.operation.type do
        :replace ->
          compact(current, operation.operation.result_context, operation.operation.reason)

        :switch ->
          project(
            value.thread,
            operation.context_ref,
            Context.new(system_prompt: profile.instructions)
          )
      end

    operation =
      if operation.operation.type == :replace,
        do: put_in(operation.operation.result_context, result),
        else: operation

    thread =
      Jido.Thread.append(value.thread, %{
        kind: :ai_context_operation,
        payload: operation,
        refs: %{op_id: operation.op_id, context_ref: operation.context_ref}
      })

    value = %{
      value
      | active_context_ref: operation.context_ref,
        pending_context_op: nil,
        thread: thread,
        applied_context_ops:
          Enum.take(
            [operation.op_id | Enum.reject(value.applied_context_ops, &(&1 == operation.op_id))],
            128
          )
    }

    candidate = Map.put(state, profile.memory.history, entry_maps(result.entries))

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

  # Ordinary history Actions and one-Turn Flows can change domain history.
  # Save that exact view before recording an operation or a new message batch.
  # This checkpoint is not another user operation and consumes no operation ID.
  defp sync(value, state, profile) do
    current = context(state, profile)

    previous =
      project(
        value.thread,
        value.active_context_ref,
        Context.new(system_prompt: profile.instructions)
      )

    if current.entries == previous.entries and current.system_prompt == previous.system_prompt do
      value
    else
      thread =
        Jido.Thread.append(value.thread, %{
          kind: :ai_context_snapshot,
          payload: %{context_ref: value.active_context_ref, result_context: current},
          refs: %{context_ref: value.active_context_ref}
        })

      %{value | thread: thread}
    end
  end

  defp context(state, profile) do
    {:ok, entries} = History.read(state, profile)

    Context.new(id: "ai:#{profile.id}", system_prompt: profile.instructions)
    |> Context.append_messages(entries)
  end

  defp append_messages(thread, entries, ref, record) do
    Jido.Thread.append(
      thread,
      Enum.map(entries, fn entry ->
        %{
          kind: :ai_message,
          payload: Map.put(entry, :context_ref, ref),
          refs:
            (Map.get(entry, :refs) || %{})
            |> Map.drop([:request_id, :run_id, :signal_id, "request_id", "run_id", "signal_id"])
            |> Map.merge(%{request_id: record.id, run_id: record.run_id})
        }
      end)
    )
  end

  defp project(thread, ref, fallback) do
    Enum.reduce(Jido.Thread.to_list(thread), fallback, fn entry, context ->
      if field(entry.payload, :context_ref) == ref do
        case entry.kind do
          :ai_context_snapshot ->
            entry.payload.result_context

          :ai_context_operation ->
            if entry.payload.operation.type == :replace,
              do: entry.payload.operation.result_context,
              else: context

          :ai_message ->
            Context.append_messages(context, [entry.payload])

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
      Enum.all?(values, fn {id, value} -> Map.has_key?(profiles, id) and valid_value?(value) end)

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
           applied_context_ops: ids,
           thread: %Jido.Thread{} = thread
         } = value
       ) do
    Map.keys(value) -- [:active_context_ref, :pending_context_op, :applied_context_ops, :thread] ==
      [] and
      nonempty?(ref) and is_list(ids) and length(ids) <= 128 and Enum.all?(ids, &nonempty?/1) and
      length(ids) == length(Enum.uniq(ids)) and (is_nil(pending) or valid_operation?(pending)) and
      valid_thread?(thread)
  end

  defp valid_value?(_), do: false

  defp valid_thread?(thread) do
    match?({:ok, _}, Zoi.parse(Jido.Thread.schema(), thread)) and
      thread.rev == length(thread.entries) and thread.stats.entry_count == length(thread.entries) and
      Enum.all?(Enum.with_index(thread.entries), fn {entry, index} ->
        valid_entry?(entry, index)
      end)
  end

  defp valid_entry?(%Jido.Thread.Entry{} = entry, index) do
    nonempty?(entry.id) and entry.seq == index and is_integer(entry.at) and
      is_atom(entry.kind) and is_map(entry.payload) and is_map(entry.refs) and
      valid_payload?(entry.kind, entry.payload)
  end

  defp valid_entry?(_, _), do: false

  defp valid_payload?(:ai_context_operation, payload), do: valid_operation?(payload)

  defp valid_payload?(:ai_context_snapshot, payload),
    do: nonempty?(payload[:context_ref]) and valid_context?(payload[:result_context])

  defp valid_payload?(:ai_message, payload),
    do: nonempty?(payload[:context_ref]) and valid_messages?([payload])

  defp valid_payload?(_, _), do: true

  defp valid_operation?(%{op_id: id, context_ref: ref, operation: operation})
       when is_map(operation) do
    nonempty?(id) and nonempty?(ref) and operation[:type] in [:replace, :switch] and
      operation[:reason] in [:manual, :restore, :compaction, :system] and
      (is_nil(operation[:base_seq]) or is_integer(operation[:base_seq])) and
      is_map(operation[:meta]) and
      case operation.type do
        :replace -> valid_context?(operation[:result_context])
        :switch -> is_nil(operation[:result_context])
      end
  end

  defp valid_operation?(_), do: false

  defp valid_context?(%Context{} = context),
    do:
      (is_nil(context.system_prompt) or is_binary(context.system_prompt)) and
        is_list(context.entries) and valid_messages?(entry_maps(context.entries))

  defp valid_context?(_), do: false

  defp valid_messages?(entries) do
    case History.messages(entries) do
      {:ok, messages} ->
        Enum.all?(messages, &match?({:ok, _}, Zoi.parse(ReqLLM.Message.schema(), &1)))

      _ ->
        false
    end
  end

  defp nonempty?(value), do: is_binary(value) and value != ""
end

defmodule Jido.AI.Context.Operations.Plugin do
  @moduledoc false
  use Jido.Plugin
  alias Jido.AI.Context.Operations, as: Ops

  def state_spec(opts),
    do: {Ops.key(), Zoi.map() |> Zoi.refine({Ops, :validate_state, [opts[:profiles]]}) |> Zoi.default(%{})}

  def directives(_), do: [Ops.Change]

  def validate_directive(%Ops.Change{} = change, opts) do
    with :ok <- Ops.validate_state(%{change.profile_id => change.value}, opts[:profiles], nil),
         do: {:ok, change}
  end

  def update_state(state, changes, _),
    do: {:ok, Enum.reduce(changes, state, &Map.put(&2, &1.profile_id, &1.value))}
end

defmodule Jido.AI.Context.Operations.Apply do
  @moduledoc false
  use Jido.Action, name: "ai_context_modify"

  def run(params, context) do
    case Jido.AI.Error.capture(fn -> Jido.AI.Context.Operations.modify(params, context) end) do
      {:error, _} when is_map_key(params, :legacy?) -> {:ok, context.agent_state}
      result -> result
    end
  end
end
