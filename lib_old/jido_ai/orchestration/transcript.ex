defmodule Jido.AI.Orchestration.Transcript do
  @moduledoc false
  # Agent field access and request-owned commits. This module owns no value.
  alias Jido.AI.Profile
  alias Jido.AI.Thread.Projection
  alias Jido.AI.Model.Messages
  alias Jido.AI.Orchestration.ExecutionBridge

  def query(query, refs),
    do: Messages.entries([%{role: :user, content: query, refs: Jido.AI.Skill.Runtime.untrusted_refs(refs)}])

  def refs(record, source) do
    record.extra_refs
    |> Map.drop([:request_id, :run_id, :signal_id, "request_id", "run_id", "signal_id"])
    |> Map.merge(%{request_id: record.id, run_id: record.run_id, context: :pending})
    |> Map.put(:source, source)
    |> Jido.AI.Skill.Runtime.untrusted_refs()
  end

  def read(_state, %{memory: %{history: nil}}), do: {:ok, []}

  def read(state, profile) when is_map(state) do
    case Map.get(state, profile.memory.history) do
      nil ->
        {:ok, []}

      %Jido.Session{} = session ->
        with {:ok, entries} <- Projection.project(session) do
          if Enum.any?(entries, &(get_in(&1, [:refs, :content_omitted]) == true)),
            do: {:error, :context_content_not_retained},
            else: {:ok, entries}
        end

      _ ->
        Profile.error("memory.history", "Expected a Jido.Session value")
    end
  end

  def read(_, _), do: Profile.error("memory.history", "Expected initialized Agent state")

  def request_refs(context, extra_refs \\ %{}) do
    {:ok, request} = ExecutionBridge.request(context)

    case request do
      nil ->
        extra_refs

      request ->
        Map.merge(
          refs(%{id: request.request_id, run_id: request.run_id, extra_refs: request.extra_refs}, request.source),
          extra_refs
        )
    end
  end

  def start(state, profile, record, source) do
    with {:ok, _} <- read(state, profile),
         do: {:ok, append(state, profile, query(record.query, refs(record, source)))}
  end

  def append(state, %{memory: %{history: nil}}, _), do: state

  def append(state, profile, entries) do
    session = Map.get(state, profile.memory.history) || Jido.Session.new()
    ref = Jido.AI.Thread.Control.active_ref(state, profile.id)

    Map.put(
      state,
      profile.memory.history,
      Projection.append_entries(session, entries, %{context_ref: ref}, profile.observability)
    )
  end

  def settle(state, %{memory: %{history: nil}}, _record), do: state

  def settle(state, profile, record) do
    session = Map.get(state, profile.memory.history)

    if session do
      entry =
        Jido.Thread.Entry.new(
          kind: :ai_request_settled,
          payload: %{status: :completed},
          refs: %{request_id: record.id, run_id: record.run_id}
        )

      Map.put(state, profile.memory.history, Jido.Session.append(session, entry))
    else
      state
    end
  end

  def record(state, entries, context) do
    {:ok, request} = ExecutionBridge.request(context)

    entries =
      case request do
        nil ->
          entries

        request ->
          refs = request_refs(context)

          Enum.map(
            entries,
            &Map.update(&1, :refs, refs, fn existing ->
              refs
              |> Map.merge(existing || %{})
              |> Map.drop([:signal_id, "request_id", "run_id", "signal_id"])
              |> Map.merge(%{request_id: request.request_id, run_id: request.run_id, context: :pending})
            end)
          )
      end

    with {:ok, _} <- ExecutionBridge.commit_entries(context, entries),
         do: {:ok, %{state | history_delta: state.history_delta ++ entries}}
  end
end
