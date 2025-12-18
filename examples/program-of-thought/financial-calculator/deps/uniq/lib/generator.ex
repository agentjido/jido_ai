defmodule Uniq.Generator do
  @moduledoc """
  This module is used to interact with the global state
  needed to correctly generate version 1 and version 6 UUIDs.

  This state consists of two atomic values: the last timestamp at
  which a UUID was generated; and the current clock sequence value.

  On init, the clock sequence is seeded with a random value provided
  by interpreting bits from the cryptographic random number generator
  as an unsigned 14 bit integer.

  On subsequent generations, the clock sequence is incremented by 1
  if a UUID has already been generated with the same last timestamp.
  If the timestamp has changed, the clock sequence remains unchanged.
  """
  use GenServer

  @compile {:inline, [get_atomic_ref: 0, now: 0]}

  @timestamp_index 1
  @clock_index 2

  @doc """
  Generates the next initial state for UUID creation.
  """
  def next do
    ref = get_atomic_ref()
    last_ts = :atomics.get(ref, @timestamp_index)
    current_ts = now()

    # Increment clock sequence if the timestamp has not changed
    if last_ts == current_ts do
      # Always increment the clock to ensure concurrent accesses 
      # are unique for the same timestamp
      clock = :atomics.add_get(ref, @clock_index, 1)

      {current_ts, clock}
    else
      clock = :atomics.add_get(ref, @clock_index, 1)
      :atomics.put(ref, @timestamp_index, current_ts)

      {current_ts, clock}
    end
  end

  ## Private

  defp get_atomic_ref do
    # By storing the atomic ref in the process state, we avoid all the
    # overhead of looking it up in an ETS table, or asking a process for it,
    # and it becomes almost as efficient as a thread local
    case Process.get(__MODULE__) do
      nil ->
        # The slow path, in this case we have to fetch the ref from the public ETS table
        [{_, ref}] = :ets.lookup(__MODULE__, :counters)
        Process.put(__MODULE__, ref)
        ref

      ref ->
        # The fast path
        ref
    end
  end

  # Obtain the current time in UTC as the number of microseconds since
  # the start of the gregorian calendar
  defp now do
    system_time = System.system_time(:microsecond)

    us = rem(system_time, 100_000)

    system_time
    |> :calendar.system_time_to_universal_time(:microsecond)
    |> :calendar.datetime_to_gregorian_seconds()
    |> Kernel.*(100_000)
    |> Kernel.+(us)
  end

  ## GenServer Implementation

  def start_link(_args), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    ref = :atomics.new(2, signed: false)

    # Seed the clock index
    <<clock::unsigned-integer-size(14), _::2>> = :crypto.strong_rand_bytes(2)
    :atomics.put(ref, @clock_index, clock)

    # Store the atomic ref in a public ETS table to avoid bottlenecks
    tab = :ets.new(__MODULE__, [:public, :named_table, {:read_concurrency, true}])

    :ets.insert(tab, {:counters, ref})

    {:ok, tab}
  end
end
