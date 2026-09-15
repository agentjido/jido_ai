defmodule Jido.AI.Session.Inspection do
  @moduledoc false
  alias Jido.AI.{Configuration, Context, History, Profile}
  alias Jido.AI.Runtime.Event

  @limit 2_000
  @terminal [:request_completed, :request_failed, :request_cancelled]

  def empty do
    %{
      events: [],
      truncated?: false,
      seq: 0,
      phase: :pending,
      streaming_text: "",
      streaming_thinking: "",
      pending_tool_calls: []
    }
  end

  def record(view, %Event{} = event) do
    view = Map.merge(empty(), view)
    saved = %{event | data: portable_data(event.data)}

    view =
      if length(view.events) < @limit,
        do: %{view | events: view.events ++ [saved]},
        else: %{view | truncated?: true}

    view
    |> Map.merge(%{seq: event.seq, llm_call_id: event.llm_call_id, model_calls: event.iteration})
    |> Map.put(:model, saved.data[:model] || view[:model])
    |> project(saved)
  end

  defp project(view, %{kind: :llm_started}) do
    Map.merge(view, %{phase: :awaiting_llm, streaming_text: "", streaming_thinking: ""})
  end

  defp project(view, %{kind: :llm_delta, data: %{delta: delta} = data}) when is_binary(delta) do
    key = if data[:chunk_type] == :thinking, do: :streaming_thinking, else: :streaming_text
    Map.update!(view, key, &(&1 <> delta))
  end

  defp project(view, %{kind: :llm_completed, data: data}) do
    view
    |> Map.put(:phase, :reasoning)
    |> complete_text(:streaming_text, data[:text])
    |> complete_text(:streaming_thinking, data[:thinking_content])
  end

  defp project(view, %{kind: :tool_started} = event) do
    call = %{
      id: event.tool_call_id,
      name: event.tool_name,
      arguments: event.data[:arguments] || %{},
      status: :running,
      result: nil
    }

    %{view | phase: :executing_tool, pending_tool_calls: view.pending_tool_calls ++ [call]}
  end

  defp project(view, %{kind: :tool_completed, tool_call_id: id}) do
    calls = Enum.reject(view.pending_tool_calls, &(&1.id == id))

    if calls == view.pending_tool_calls do
      view
    else
      %{
        view
        | pending_tool_calls: calls,
          phase: if(calls == [], do: :reasoning, else: :executing_tool)
      }
    end
  end

  defp project(view, %{kind: :checkpoint, data: data}),
    do: Map.merge(view, %{phase: :checkpoint, checkpoint_token: data[:token]})

  defp project(view, %{kind: kind, data: data})
       when kind in [:output_started, :output_validated, :output_repair, :output_failed],
       do: Map.put(view, :output_event, data)

  defp project(view, %{kind: kind}) when kind in @terminal,
    do: %{view | phase: kind, pending_tool_calls: []}

  defp project(view, _), do: view

  defp complete_text(view, key, text) when is_binary(text) and text != "",
    do: Map.put(view, key, text)

  defp complete_text(view, _, _), do: view

  # Checkpoints are transfer data, not a nested trace. Keep live tool effects
  # out of portable state without changing the canonical caller event.
  defp portable_data(data) do
    data = Map.drop(data, [:react_checkpoint])

    data =
      if is_map(data[:meta]),
        do: Map.update!(data, :meta, &Map.drop(&1, [:react_checkpoint])),
        else: data

    case Jido.Action.validate_static_data(data) do
      :ok -> data
      _ -> Jido.AI.Observe.sanitize_transport_payload(data)
    end
  end

  # The trace is an observed prefix, sampled before the outcome commit.
  # Cancellation can race with further live events. Do not invent a stream
  # event inside a pure Turn or reserve its sequence number before commit.
  def complete(record, view, candidate, context) do
    if get_in(record, [:meta, :completion, :details_elided?]) do
      Map.put(record, :inspection, %{truncated?: true})
    else
      view =
        Map.merge(empty(), view || %{})
        |> Map.merge(%{phase: terminal_kind(record), pending_tool_calls: []})

      record |> Map.put(:inspection, view) |> fit(candidate, context)
    end
  end

  def fit(record, candidate, context) do
    limit = Jido.AI.Runtime.StateSize.limit(context.jido_ai_agent)
    state = put_in(candidate, [:requests, record.id], record)

    if is_integer(limit) and :erlang.external_size(state) > limit,
      do: Map.put(record, :inspection, %{truncated?: true, seq: record.inspection[:seq] || 0}),
      else: record
  end

  defp terminal_kind(%{status: :completed}), do: :request_completed
  defp terminal_kind(%{error: :cancelled}), do: :request_cancelled
  defp terminal_kind(%{error: {:cancelled, _}}), do: :request_cancelled
  defp terminal_kind(_), do: :request_failed

  def selected(agent, id) do
    records = Map.get(agent.state, :requests, %{})

    if id do
      records[id]
    else
      records
      |> Map.values()
      |> Enum.max_by(&{&1.status == :pending, &1.inserted_at, &1.id}, fn -> nil end)
    end
  end

  def snapshot(snapshot, request, live) do
    records = Map.get(snapshot.agent.state, :requests, %{})

    inspection =
      if request, do: Map.merge(empty(), Map.get(request, :inspection, %{})), else: empty()

    meta = if request, do: request.meta, else: %{}
    inspection = if live, do: live.inspection, else: inspection
    meta = if live, do: live.meta, else: meta

    profile =
      case Configuration.profile(snapshot.agent, request && Map.get(request, :profile_id)) do
        {:ok, profile} -> profile
        {:error, _} -> nil
      end

    profile_id =
      case request do
        %{profile_id: id} -> id
        _ -> profile && profile.id
      end

    lane = get_in(snapshot.agent.state, [Context.Operations.key(), profile_id]) || %{}
    conversation = conversation(snapshot.agent.state, profile)

    details = %{
      phase: phase(request, inspection, live),
      iteration: meta[:reasoning_iteration],
      reasoning: if(live, do: live.reasoning, else: retained_reasoning(request)),
      model_calls: meta[:model_calls],
      model: inspection[:model],
      termination_reason: meta[:termination_reason],
      streaming_text: inspection.streaming_text,
      streaming_thinking: inspection.streaming_thinking,
      thinking_trace: Map.get(meta, :thinking_trace, []),
      usage: Map.get(meta, :usage, %{}),
      output: meta[:output],
      duration_ms: duration(request),
      tool_calls: inspection.pending_tool_calls,
      tool_results: Map.get(meta, :tool_results, []),
      current_llm_call_id: inspection[:llm_call_id],
      active_request_id: if(request && request.status == :pending, do: request.id),
      active_context_ref: if(conversation, do: Map.get(lane, :active_context_ref, "default")),
      pending_context_op: lane[:pending_context_op],
      checkpoint_token: inspection[:checkpoint_token],
      cancel_reason: cancel_reason(request),
      trace: Map.take(inspection, [:events, :truncated?, :seq]) |> Map.put(:scope, :observed_prefix),
      trace_summary:
        Map.new(records, fn {id, record} ->
          trace =
            if request && id == request.id,
              do: inspection,
              else: Map.merge(empty(), Map.get(record, :inspection, %{}))

          {id, %{events: length(trace.events), truncated?: trace.truncated?}}
        end),
      config: config(profile),
      conversation: conversation || []
    }

    Map.merge(snapshot, %{
      request: request,
      details: details,
      live: live && Map.drop(live, [:inspection, :meta, :reasoning])
    })
  end

  defp config(nil), do: %{}

  defp config(%Profile{} = profile) do
    entry = profile.models[profile.reasoning.model]

    Map.get(profile.reasoning, :options, %{})
    |> Map.merge(Map.new(entry.generation))
    |> Map.merge(%{
      model: entry.model,
      system_prompt: profile.instructions,
      base_tool_context: profile.tool_context,
      tools: Enum.map(profile.tools, & &1.target),
      actions_by_name: Map.new(profile.tools, &{&1.name, &1.target}),
      reqllm_tools: Jido.AI.ToolCatalog.definitions(profile.tools),
      max_iterations: profile.controls.max_iterations,
      max_tool_calls: profile.controls.max_tool_calls,
      request_policy: profile.requests.on_busy,
      streaming: profile.requests.streaming
    })
  end

  defp conversation(_, nil), do: nil
  defp conversation(_, %{memory: %{history: nil}}), do: nil

  defp conversation(state, profile) do
    case History.read(state, profile) do
      {:ok, entries} ->
        Context.new(system_prompt: profile.instructions)
        |> Context.append_messages(entries)
        |> Context.to_messages()

      {:error, _} ->
        nil
    end
  end

  defp phase(nil, _, _), do: :idle
  defp phase(%{status: :pending}, inspection, _), do: inspection.phase
  defp phase(record, _, _), do: terminal_kind(record)

  defp retained_reasoning(%{meta: %{reasoning: reasoning}}), do: reasoning
  defp retained_reasoning(%{error: {:failed, _, %{trm: data}}}), do: %{method: :trm, trm: data}
  defp retained_reasoning(_), do: nil

  defp duration(nil), do: nil

  defp duration(record),
    do: max((record.completed_at || System.system_time(:millisecond)) - record.inserted_at, 0)

  defp cancel_reason(%{error: {:cancelled, reason}}), do: reason
  defp cancel_reason(%{error: :cancelled}), do: :cancelled
  defp cancel_reason(_), do: nil
end
