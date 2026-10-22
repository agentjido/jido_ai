defmodule Jido.AI.Request.Metadata do
  @moduledoc false

  def from_snapshot(snapshot, overrides \\ %{}) do
    Map.merge(snapshot_request_meta(snapshot), normalize_meta(overrides))
  end

  def record_turn(meta, data) do
    details = %{
      reasoning_details: get_field(data, :reasoning_details),
      streaming_thinking: get_field(data, :thinking_content)
    }

    derived = from_snapshot(%{details: details})
    meta = meta |> Map.delete(:last_thinking) |> Map.merge(derived)

    case normalize_non_empty_string(get_field(data, :thinking_content)) do
      nil ->
        meta

      thinking ->
        entry = %{
          call_id: get_field(data, :call_id),
          iteration: get_field(data, :iteration),
          thinking: thinking
        }

        Map.update(meta, :thinking_trace, [entry], &(&1 ++ [entry]))
    end
  end

  defp snapshot_request_meta(snapshot) when is_map(snapshot) do
    case get_field(snapshot, :details) do
      details when is_map(details) -> snapshot_request_meta(details, snapshot)
      _ -> %{}
    end
  end

  defp snapshot_request_meta(_), do: %{}

  defp snapshot_request_meta(details, snapshot) do
    %{}
    |> maybe_put_meta(:usage, extract_snapshot_usage(details, snapshot))
    |> maybe_put_meta(:output, normalize_non_empty_map(get_field(details, :output)))
    |> maybe_put_meta(:reasoning_details, extract_snapshot_reasoning_details(details, snapshot))
    |> maybe_put_meta(
      :thinking_trace,
      normalize_non_empty_list(get_field(details, :thinking_trace))
    )
    |> maybe_put_meta(:last_thinking, extract_snapshot_last_thinking(details, snapshot))
  end

  defp extract_snapshot_usage(details, snapshot) do
    details
    |> get_field(:usage, get_field(snapshot, :result) |> get_field(:usage))
    |> normalize_non_empty_map()
  end

  defp extract_snapshot_reasoning_details(details, snapshot) do
    details
    |> get_field(
      :reasoning_details,
      get_field(snapshot, :result) |> get_field(:reasoning_details)
    )
    |> normalize_non_empty_list()
    |> case do
      nil -> extract_reasoning_details_from_context(get_field(details, :context))
      reasoning_details -> reasoning_details
    end
  end

  defp extract_snapshot_last_thinking(details, snapshot) do
    details
    |> get_field(:streaming_thinking, get_field(details, :last_thinking))
    |> normalize_non_empty_string()
    |> case do
      nil ->
        snapshot
        |> get_field(:result)
        |> get_field(:thinking_content)
        |> normalize_non_empty_string()

      last_thinking ->
        last_thinking
    end
  end

  defp extract_reasoning_details_from_context(conversation) when is_list(conversation) do
    conversation
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      case get_field(message, :role) do
        role when role in [:assistant, "assistant"] ->
          message
          |> get_field(:reasoning_details)
          |> normalize_non_empty_list()

        _ ->
          nil
      end
    end)
  end

  defp extract_reasoning_details_from_context(_), do: nil

  defp maybe_put_meta(meta, _key, nil), do: meta
  defp maybe_put_meta(meta, key, value), do: Map.put(meta, key, value)

  defp normalize_meta(meta) when is_map(meta), do: meta
  defp normalize_meta(_), do: %{}

  defp normalize_non_empty_map(map) when is_map(map) and map != %{}, do: map
  defp normalize_non_empty_map(_), do: nil

  defp normalize_non_empty_list(list) when is_list(list) and list != [], do: list
  defp normalize_non_empty_list(_), do: nil

  defp normalize_non_empty_string(value) when is_binary(value) and value != "", do: value
  defp normalize_non_empty_string(_), do: nil

  defp get_field(map, key, default \\ nil)
  defp get_field(map, _key, default) when not is_map(map), do: default

  defp get_field(map, key, default) when is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
