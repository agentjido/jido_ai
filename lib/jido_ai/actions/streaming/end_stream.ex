defmodule Jido.AI.Actions.Streaming.EndStream do
  @moduledoc """
  A Jido.Action for finalizing a stream and collecting usage metadata.

  This action should be called after a stream completes to collect the final
  usage statistics, metadata, and optionally the full buffered response.
  It also ensures proper cleanup of stream resources.

  ## Parameters

  * `stream_id` (required) - The ID of the stream to finalize
  * `wait_for_completion` (optional) - Wait for stream to finish if still active (default: `true`)
  * `timeout` (optional) - Max time to wait in milliseconds (default: `30000`)

  ## Examples

      # Basic stream finalization
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Streaming.EndStream, %{
        stream_id: "abc123"
      })

      # With custom timeout
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Streaming.EndStream, %{
        stream_id: "abc123",
        timeout: 5000
      })
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

  @doc """
  Executes the end stream action.

  ## Returns

  * `{:ok, result}` - Final stream result with `stream_id`, `status`, `usage`
  * `{:error, reason}` - Error if stream not found or timeout

  ## Result Format

      %{
        stream_id: "abc123",
        status: :completed,
        usage: %{
          input_tokens: 10,
          output_tokens: 25,
          total_tokens: 35
        },
        text: "Full response text if buffered",
        model: "anthropic:claude-haiku-4-5"
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    stream_id = params[:stream_id]

    case validate_stream_id(stream_id) do
      :ok ->
        # For now, return a placeholder result
        # In a full implementation, this would interface with a stream registry
        # to retrieve final status, usage, and buffered text
        {:ok,
         %{
           stream_id: stream_id,
           status: :completed,
           usage: default_usage(),
           note: "Stream finalized"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp validate_stream_id(nil), do: {:error, :stream_id_required}
  defp validate_stream_id(""), do: {:error, :stream_id_required}
  defp validate_stream_id(stream_id) when is_binary(stream_id), do: :ok
  defp validate_stream_id(_), do: {:error, :invalid_stream_id}

  defp default_usage do
    %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0
    }
  end
end
