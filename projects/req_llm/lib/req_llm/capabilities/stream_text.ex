defmodule ReqLLM.Capabilities.StreamText do
  @moduledoc """
  Stream text capability verification for AI models.

  Verifies that a model can perform text streaming by sending
  a message and validating the streamed response.
  """

  @behaviour ReqLLM.Capability

  @impl true
  def id, do: :stream_text

  @impl true
  def advertised?(_model) do
    # Stream text may not be available for all models, but we'll test it
    true
  end

  @impl true
  def verify(model, opts) do
    model_spec = "#{model.provider}:#{model.model}"
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Use provider_options to pass timeout to the HTTP client
    req_llm_opts = [
      provider_options: %{
        receive_timeout: timeout,
        timeout: timeout
      }
    ]

    try do
      case ReqLLM.stream_text(
             model_spec,
             "Hello! Please respond with exactly 3 words.",
             req_llm_opts
           ) do
        {:ok, %Req.Response{headers: headers} = response} ->
          # Check if this is an SSE response that should be streamed
          content_type = Map.get(headers, "content-type", []) |> List.first() || ""

          if String.contains?(content_type, "text/event-stream") do
            # Process the SSE response into a stream
            processed = ReqLLM.Plugins.Stream.process_sse_response(response)

            if is_struct(processed.body, Stream) do
              # Collect streamed chunks
              chunks =
                processed.body
                # Limit chunks to avoid infinite streams
                |> Enum.take(100)
                |> Enum.to_list()

              if length(chunks) > 0 do
                # Extract text from content_block_delta chunks
                text_chunks =
                  chunks
                  |> Enum.filter(fn chunk ->
                    match?(%{data: %{"type" => "content_block_delta"}}, chunk)
                  end)
                  |> Enum.map(fn %{data: %{"delta" => %{"text" => text}}} -> text end)

                full_response = Enum.join(text_chunks, "")
                trimmed = String.trim(full_response)

                if trimmed != "" do
                  {:ok,
                   %{
                     model_id: model_spec,
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
            else
              {:error, "SSE response was not processed into a stream"}
            end
          else
            {:error, "Response is not a streaming response (content-type: #{content_type})"}
          end

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, "Unexpected response format: #{inspect(other)}"}
      end
    rescue
      error -> {:error, "Exception during streaming: #{inspect(error)}"}
    end
  end
end
