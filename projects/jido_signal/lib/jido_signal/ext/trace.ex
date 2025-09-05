defmodule Jido.Signal.Ext.Trace do
  @moduledoc """
  Trace extension for Jido Signal correlation and debugging.

  Provides four simple fields for tracking signal causation:
  * `trace_id` - constant for entire call chain
  * `span_id` - unique for this signal  
  * `parent_span_id` - span that triggered this signal
  * `causation_id` - signal ID that caused this signal

  Serializes to CloudEvents attributes: trace_id, span_id, parent_span_id, causation_id
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
      "trace_id" => trace_id,
      "span_id" => span_id
    }
    |> maybe_put("parent_span_id", data[:parent_span_id])
    |> maybe_put("causation_id", data[:causation_id])
  end

  @impl true
  def from_attrs(attrs) do
    case Map.get(attrs, "trace_id") do
      nil ->
        nil

      trace_id ->
        %{
          trace_id: trace_id,
          span_id: Map.get(attrs, "span_id")
        }
        |> maybe_put_field(:parent_span_id, Map.get(attrs, "parent_span_id"))
        |> maybe_put_field(:causation_id, Map.get(attrs, "causation_id"))
    end
  end

  defp maybe_put_field(map, _key, nil), do: map
  defp maybe_put_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
