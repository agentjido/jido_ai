defmodule Jido.AI.Actions.Streaming.EndStream do
  @moduledoc """
  A Jido.Action for finalizing a stream and collecting usage metadata.

  This action reads stream lifecycle state from `Jido.AI.Streaming.Registry`.
  """

  use Jido.Action,
    name: "streaming_end",
    description: "Finalize a stream and collect usage metadata",
    category: "ai",
    tags: ["streaming", "llm", "cleanup"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        stream_id: Zoi.string(description: "The ID of the stream to finalize"),
        wait_for_completion:
          Zoi.boolean(description: "Wait for stream to finish if still active")
          |> Zoi.default(true)
          |> Zoi.optional(),
        timeout:
          Zoi.integer(description: "Max time to wait in milliseconds")
          |> Zoi.default(30_000)
          |> Zoi.optional()
      })

  alias Jido.AI.Streaming.Registry

  @impl Jido.Action
  def run(params, _context) do
    stream_id = params[:stream_id]
    wait? = Map.get(params, :wait_for_completion, true)
    timeout = Map.get(params, :timeout, 30_000)

    with :ok <- validate_stream_id(stream_id),
         {:ok, entry} <- fetch_entry(stream_id, wait?, timeout) do
      {:ok, format_result(entry)}
    end
  end

  defp fetch_entry(stream_id, true, timeout), do: Registry.wait_for_terminal(stream_id, timeout)
  defp fetch_entry(stream_id, false, _timeout), do: Registry.get(stream_id)

  defp format_result(entry) do
    %{
      stream_id: entry.stream_id,
      status: entry.status,
      usage: Map.get(entry, :usage, default_usage()),
      text: Map.get(entry, :text),
      model: Map.get(entry, :model),
      token_count: Map.get(entry, :token_count, 0),
      error: Map.get(entry, :error)
    }
  end

  defp validate_stream_id(nil), do: {:error, :stream_id_required}
  defp validate_stream_id(""), do: {:error, :stream_id_required}
  defp validate_stream_id(stream_id) when is_binary(stream_id), do: :ok
  defp validate_stream_id(_), do: {:error, :invalid_stream_id}

  defp default_usage do
    %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
  end
end
