defmodule ReqLLM.Capability.StreamText do
  @moduledoc """
  Stream text capability verification for AI models.

  Verifies that a model can perform text streaming by sending
  a message and validating the streamed response.
  """
  alias ReqLLM.StreamChunk

  @behaviour ReqLLM.Capability.Adapter

  @impl true
  def id, do: :stream_text

  @impl true
  def advertised?(_model) do
    # Stream text may not be available for all models, but we'll test it
    true
  end

  @impl true
  def verify(model, opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Use provider_options to pass timeout to the HTTP client
    req_llm_opts = [
      provider_options: %{
        receive_timeout: timeout,
        timeout: timeout
      }
    ]

    case ReqLLM.stream_text!(model, "Hello! Please respond with exactly 3 words.", req_llm_opts) do
      {:ok, stream} when is_struct(stream, Stream) ->
        # Collect StreamChunk structs from the stream
        chunks =
          stream
          # Limit chunks to avoid infinite streams
          |> Enum.take(100)
          |> Enum.to_list()

        if length(chunks) > 0 do
          # Extract text from content StreamChunks
          text_chunks =
            chunks
            |> Enum.filter(fn chunk ->
              match?(%StreamChunk{type: :content}, chunk)
            end)
            |> Enum.map(fn %StreamChunk{text: text} -> text end)
            |> Enum.reject(&is_nil/1)

          full_response = Enum.join(text_chunks, "")
          trimmed = String.trim(full_response)

          if trimmed != "" do
            {:ok,
             %{
               model_id: "#{model.provider}:#{model.model}",
               chunks_received: length(chunks),
               text_chunks_received: length(text_chunks),
               response_length: String.length(full_response),
               response_preview: String.slice(full_response, 0, 50)
             }}
          else
            {:error, "Empty streamed response"}
          end
        else
          {:error, "No chunks received from stream"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
