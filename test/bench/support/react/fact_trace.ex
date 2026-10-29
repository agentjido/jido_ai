defmodule JidoAI.Bench.ReAct.FactTrace do
  @moduledoc false

  alias Runic.Identity
  alias Runic.Workflow.Fact

  def start!(round_counter) do
    {:module, Fact} = Code.ensure_loaded(Fact)
    collector = spawn_link(fn -> collect(round_counter, initial()) end)

    1 = :erlang.trace_pattern({Fact, :new, 1}, true, [])
    _traced = :erlang.trace(:all, true, [:call, {:tracer, collector}])

    %{collector: collector}
  end

  def stop!(%{collector: collector}) do
    disable!()
    barrier = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^barrier} -> :ok
    after
      5_000 -> raise "timed out while draining Runic fact trace"
    end

    ref = make_ref()
    send(collector, {:snapshot, self(), ref})

    receive do
      {^ref, summary} -> summary
    after
      5_000 -> raise "timed out while collecting Runic fact metrics"
    end
  end

  def disable! do
    _count = :erlang.trace(:all, false, [:call])
    _matched = :erlang.trace_pattern({Fact, :new, 1}, false, [])
    :ok
  end

  def abort!(%{collector: collector}) do
    disable!()
    send(collector, :stop)
    :ok
  end

  defp initial do
    %{
      fact_count: 0,
      largest_items: 0,
      largest_external_bytes: 0,
      largest_round: 0,
      largest_shape: nil,
      largest_child_items: [],
      rounds: %{}
    }
  end

  defp collect(round_counter, state) do
    receive do
      {:trace, _pid, :call, {Fact, :new, [params]}} ->
        value = fetch_value!(params)
        items = item_count(value)
        external_bytes = :erlang.external_size(value)
        round = :atomics.get(round_counter, 1)
        fact_count = state.fact_count + 1

        round_metrics =
          state.rounds
          |> Map.get(round, %{fact_count: 0, largest_items: 0, largest_external_bytes: 0})
          |> Map.update!(:fact_count, &(&1 + 1))
          |> Map.update!(:largest_items, &max(&1, items))
          |> Map.update!(:largest_external_bytes, &max(&1, external_bytes))

        state =
          state
          |> Map.put(:fact_count, fact_count)
          |> Map.put(:rounds, Map.put(state.rounds, round, round_metrics))
          |> maybe_largest(value, items, external_bytes, round)

        collect(round_counter, state)

      {:snapshot, caller, ref} ->
        send(caller, {ref, state})

      :stop ->
        :ok

      _other ->
        collect(round_counter, state)
    end
  end

  defp maybe_largest(state, value, items, external_bytes, round)
       when items > state.largest_items do
    %{
      state
      | largest_items: items,
        largest_external_bytes: external_bytes,
        largest_round: round,
        largest_shape: value_shape(value),
        largest_child_items: child_items(value)
    }
  end

  defp maybe_largest(state, _value, _items, _external_bytes, _round), do: state

  defp child_items(value) when is_list(value), do: Enum.map(value, &item_count/1)
  defp child_items(_value), do: []

  defp value_shape(value) when is_list(value) do
    children = value |> Enum.map(&value_shape/1) |> Enum.join(", ")
    "list(#{length(value)})[#{children}]"
  end

  defp value_shape({:jido_flow_frame, 1, _input, results, _effects}) do
    "flow_frame(results=#{result_names(results)})"
  end

  defp value_shape({:jido_nested_flow_frame, 1, _parent, child} = frame) do
    "nested_frame(depth=#{frame_depth(frame)}, leaf=#{value_shape(child)})"
  end

  defp value_shape(value) when is_tuple(value) and tuple_size(value) > 0 do
    "tuple(#{inspect(elem(value, 0))})"
  end

  defp value_shape(%module{}), do: "struct(#{inspect(module)})"
  defp value_shape(value) when is_map(value), do: "map(keys=#{result_names(value)})"
  defp value_shape(value) when is_atom(value), do: "atom(#{value})"

  defp value_shape(value),
    do: value |> :erlang.term_to_binary() |> byte_size() |> then(&"scalar(#{&1}B)")

  defp frame_depth({:jido_nested_flow_frame, 1, parent, _child}), do: 1 + frame_depth(parent)
  defp frame_depth(_value), do: 0

  defp result_names(map) do
    map
    |> Map.keys()
    |> Enum.map(&inspect/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp item_count(value)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_float(value) or
              is_binary(value) or is_atom(value),
       do: 1

  defp item_count(%Identity{}), do: 1

  defp item_count(%module{} = value) do
    document = Runic.Identity.Projectable.identity_document(value)
    item_count({module, document})
  end

  defp item_count(value) when is_list(value),
    do: 1 + Enum.reduce(value, 0, fn item, total -> total + item_count(item) end)

  defp item_count(value) when is_tuple(value),
    do:
      1 +
        (value
         |> Tuple.to_list()
         |> Enum.reduce(0, fn item, total -> total + item_count(item) end))

  defp item_count(value) when is_map(value) do
    1 +
      Enum.reduce(value, 0, fn {key, item}, total ->
        total + item_count(key) + item_count(item)
      end)
  end

  defp fetch_value!(params) when is_list(params), do: Keyword.fetch!(params, :value)
  defp fetch_value!(params) when is_map(params), do: Map.fetch!(params, :value)
end
