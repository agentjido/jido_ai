defmodule Jido.AI.Actions.Streaming.ProcessTokens do
  @moduledoc """
  A Jido.Action for processing tokens from an active stream.

  This action consumes the stream response stored in
  `Jido.AI.Streaming.Registry`, applies optional callbacks/filtering, and
  updates stream lifecycle state.
  """

  use Jido.Action,
    name: "streaming_process_tokens",
    description: "Process tokens from an active stream",
    category: "ai",
    tags: ["streaming", "llm", "tokens"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        stream_id: Zoi.string(description: "The ID of the stream to process"),
        on_token: Zoi.any(description: "Callback function invoked for each token") |> Zoi.optional(),
        on_complete:
          Zoi.any(description: "Callback function invoked when stream completes")
          |> Zoi.optional(),
        filter:
          Zoi.any(description: "Function to filter tokens (return true to include)")
          |> Zoi.optional(),
        transform: Zoi.any(description: "Function to transform each token") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Streaming.Registry

  @impl Jido.Action
  def run(params, _context) do
    stream_id = params[:stream_id]

    with :ok <- validate_stream_id(stream_id),
         {:ok, entry} <- Registry.get(stream_id) do
      maybe_process(entry, params)
    end
  end

  defp maybe_process(%{status: status} = entry, _params) when status in [:completed, :error] do
    {:ok, format_result(entry)}
  end

  defp maybe_process(%{stream_response: nil}, _params), do: {:error, :stream_not_processible}

  defp maybe_process(entry, params) do
    stream_id = entry.stream_id
    on_token = params[:on_token] || entry[:on_token]
    on_complete = params[:on_complete]
    filter = params[:filter]
    transform = params[:transform]

    with {:ok, _entry} <- Registry.mark_processing(stream_id),
         {:ok, response} <-
           ReqLLM.StreamResponse.process_stream(entry.stream_response,
             on_result: fn chunk ->
               handle_chunk(stream_id, chunk, on_token, filter, transform)
             end
           ),
         usage = Helpers.extract_usage(response),
         {:ok, completed_entry} <-
           Registry.mark_completed(stream_id, %{usage: usage, response: response, stream_response: nil}) do
      maybe_invoke_on_complete(on_complete, completed_entry)
      {:ok, format_result(completed_entry)}
    else
      {:error, reason} = error ->
        _ = Registry.mark_error(stream_id, reason)

        with {:ok, failed_entry} <- Registry.get(stream_id) do
          maybe_invoke_on_complete(on_complete, failed_entry)
        end

        error
    end
  end

  defp handle_chunk(stream_id, chunk, on_token, filter, transform) when is_binary(chunk) do
    if include_token?(chunk, filter) do
      token = transform_token(chunk, transform)
      _ = Registry.append_token(stream_id, token)
      maybe_invoke_on_token(on_token, token)
    end

    :ok
  end

  defp handle_chunk(_stream_id, _chunk, _on_token, _filter, _transform), do: :ok

  defp include_token?(_token, nil), do: true

  defp include_token?(token, filter) when is_function(filter, 1) do
    try do
      filter.(token)
    rescue
      _ -> true
    catch
      _, _ -> true
    end
  end

  defp include_token?(_token, _filter), do: true

  defp transform_token(token, nil), do: token

  defp transform_token(token, transform) when is_function(transform, 1) do
    try do
      transformed = transform.(token)
      if is_binary(transformed), do: transformed, else: token
    rescue
      _ -> token
    catch
      _, _ -> token
    end
  end

  defp transform_token(token, _transform), do: token

  defp maybe_invoke_on_token(nil, _token), do: :ok

  defp maybe_invoke_on_token(on_token, token) when is_function(on_token, 1) do
    try do
      on_token.(token)
      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp maybe_invoke_on_token(_on_token, _token), do: :ok

  defp maybe_invoke_on_complete(nil, _result), do: :ok

  defp maybe_invoke_on_complete(on_complete, result) when is_function(on_complete, 1) do
    try do
      on_complete.(format_result(result))
      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp maybe_invoke_on_complete(_on_complete, _result), do: :ok

  defp format_result(entry) do
    %{
      stream_id: entry.stream_id,
      status: entry.status,
      token_count: Map.get(entry, :token_count, 0),
      text: Map.get(entry, :text, ""),
      usage: Map.get(entry, :usage, %{input_tokens: 0, output_tokens: 0, total_tokens: 0}),
      model: Map.get(entry, :model),
      error: Map.get(entry, :error)
    }
  end

  defp validate_stream_id(nil), do: {:error, :stream_id_required}
  defp validate_stream_id(""), do: {:error, :stream_id_required}
  defp validate_stream_id(stream_id) when is_binary(stream_id), do: :ok
  defp validate_stream_id(_), do: {:error, :invalid_stream_id}
end
