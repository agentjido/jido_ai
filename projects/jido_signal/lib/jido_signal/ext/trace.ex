defmodule Jido.Signal.Ext.Trace do
  @moduledoc """
  Trace extension for Jido Signal correlation and debugging.

  Provides four simple fields for tracking signal causation:
  * `trace_id` - constant for entire call chain
  * `span_id` - unique for this signal  
  * `parent_span_id` - span that triggered this signal
  * `causation_id` - signal ID that caused this signal

  Serializes to compact CloudEvents attributes: traceid, spanid, parentspan, causationid
  """

  use Jido.Signal.Ext,
    namespace: "correlation",
    schema: [
      trace_id: [type: :string, required: true, doc: "Shared trace identifier"],
      span_id: [type: :string, required: true, doc: "Unique span identifier"],
      parent_span_id: [type: :string, doc: "Parent span identifier"],
      causation_id: [type: :string, doc: "Causing signal ID"]
    ]

  @impl true
  def to_attrs(%{trace_id: trace_id, span_id: span_id} = data) do
    %{
      "traceid" => trace_id,
      "spanid" => span_id
    }
    |> maybe_put("parentspan", data[:parent_span_id])
    |> maybe_put("causationid", data[:causation_id])
  end

  @impl true
  def from_attrs(attrs) do
    case Map.get(attrs, "traceid") do
      nil ->
        nil

      trace_id ->
        %{
          trace_id: trace_id,
          span_id: Map.get(attrs, "spanid"),
          parent_span_id: Map.get(attrs, "parentspan"),
          causation_id: Map.get(attrs, "causationid")
        }
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
