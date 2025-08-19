defmodule Jido.Signal.Journal.Adapters.InMemory do
  @moduledoc """
  In-memory implementation of the Journal persistence behavior.
  Uses Agent to maintain state.
  """
  @behaviour Jido.Signal.Journal.Persistence

  use Agent

  @impl true
  def init do
    case Agent.start_link(fn ->
           %{
             signals: %{},
             causes: %{},
             effects: %{},
             conversations: %{}
           }
         end) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def put_signal(signal, pid \\ nil) do
    target = pid || __MODULE__

    Agent.update(target, fn state ->
      put_in(state, [:signals, signal.id], signal)
    end)
  end

  @impl true
  def get_signal(signal_id, pid \\ nil) do
    target = pid || __MODULE__

    case Agent.get(target, fn state -> get_in(state, [:signals, signal_id]) end) do
      nil -> {:error, :not_found}
      signal -> {:ok, signal}
    end
  end

  @impl true
  def put_cause(cause_id, effect_id, pid \\ nil) do
    target = pid || __MODULE__

    Agent.update(target, fn state ->
      state
      |> update_in([:causes, cause_id], &MapSet.put(&1 || MapSet.new(), effect_id))
      |> update_in([:effects, effect_id], &MapSet.put(&1 || MapSet.new(), cause_id))
    end)
  end

  @impl true
  def get_effects(signal_id, pid \\ nil) do
    target = pid || __MODULE__
    {:ok, Agent.get(target, fn state -> get_in(state, [:causes, signal_id]) || MapSet.new() end)}
  end

  @impl true
  def get_cause(signal_id, pid \\ nil) do
    target = pid || __MODULE__

    case Agent.get(target, fn state -> get_in(state, [:effects, signal_id]) end) do
      nil -> {:error, :not_found}
      effects -> {:ok, MapSet.to_list(effects) |> List.first()}
    end
  end

  @impl true
  def put_conversation(conversation_id, signal_id, pid \\ nil) do
    target = pid || __MODULE__

    Agent.update(target, fn state ->
      update_in(
        state,
        [:conversations, conversation_id],
        &MapSet.put(&1 || MapSet.new(), signal_id)
      )
    end)
  end

  @impl true
  def get_conversation(conversation_id, pid \\ nil) do
    target = pid || __MODULE__

    {:ok,
     Agent.get(target, fn state ->
       get_in(state, [:conversations, conversation_id]) || MapSet.new()
     end)}
  end

  @doc """
  Gets all signals in the journal.

  ## Returns

  A list of all signals stored in the journal

  ## Examples

      iex> Jido.Signal.Journal.Adapters.InMemory.put_signal(signal1)
      iex> Jido.Signal.Journal.Adapters.InMemory.put_signal(signal2)
      iex> signals = Jido.Signal.Journal.Adapters.InMemory.get_all_signals()
      iex> length(signals)
      2
  """
  @spec get_all_signals(pid() | nil) :: [Jido.Signal.t()]
  def get_all_signals(pid \\ nil) do
    target = pid || __MODULE__

    Agent.get(target, fn state ->
      state.signals
      |> Map.values()
    end)
  end
end
