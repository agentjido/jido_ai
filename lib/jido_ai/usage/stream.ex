defmodule Jido.AI.Usage.Stream do
  @moduledoc false
  alias Jido.AI.Usage

  # The ReqLLM consumer invokes callbacks in this process. Each call has its
  # own reference; the after clause clears scratch state even on failure.
  def process(%ReqLLM.StreamResponse{} = stream, callbacks) do
    key = {__MODULE__, make_ref()}

    chunks =
      Elixir.Stream.transform(
        stream.stream,
        fn -> nil end,
        fn chunk, accumulated ->
          case chunk_usage(chunk) do
            usage when is_map(usage) and map_size(usage) > 0 ->
              normalized = %{chunk | metadata: Map.put(chunk.metadata, :usage, normalize(usage))}
              {[normalized], merge(accumulated, usage)}

            _ ->
              {[chunk], accumulated}
          end
        end,
        fn accumulated ->
          # ReqLLM closes its metadata handle after materialization. Read it
          # after normal stream exhaustion while that handle is still live.
          Process.put(key, {metadata_usage(stream), accumulated})
          {[], accumulated}
        end,
        fn _ -> :ok end
      )

    try do
      with {:ok, response} <-
             ReqLLM.StreamResponse.process_stream(%{stream | stream: chunks}, callbacks) do
        {metadata, captured} = Process.get(key, {nil, nil})
        {:ok, %{response | usage: select(response.usage, metadata, captured)}}
      end
    after
      Process.delete(key)
    end
  end

  def select(processed, metadata, chunks) do
    Enum.find_value([processed, metadata, chunks], &normalize/1)
  end

  def merge(existing, incoming) do
    case normalize(incoming) do
      nil ->
        existing

      incoming ->
        existing = normalize(existing) || %{}
        previous = Usage.token_counts(existing)
        current = Usage.token_counts(incoming)

        existing
        |> Map.merge(incoming)
        |> Map.merge(Map.new(current, fn {key, value} -> {key, max(previous[key], value)} end))
    end
  end

  defp normalize(usage) when is_map(usage) and map_size(usage) > 0,
    do: usage |> Usage.normalize() |> Usage.with_token_counts()

  defp normalize(_), do: nil

  defp chunk_usage(%{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, :usage) || Map.get(metadata, "usage")

  defp chunk_usage(_), do: nil

  defp metadata_usage(stream) do
    ReqLLM.StreamResponse.usage(stream)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end
end
