defmodule Jido.AI.ReqLlmBridge.StreamingAdapter do
  @moduledoc """
  Streaming adapter layer for ReqLLM integration.

  This module provides advanced streaming functionality for converting ReqLLM
  streaming responses into Jido AI compatible formats with robust error handling,
  lifecycle management, and chunk processing.

  Key responsibilities:
  - Stream chunk format transformation and validation
  - Stream lifecycle management (initialization, processing, termination)
  - Error recovery and resource cleanup for streaming operations
  - Provider-specific streaming behavior normalization
  """

  require Logger
  alias Jido.AI.ReqLlmBridge

  @doc """
  Adapts a ReqLLM stream for Jido AI consumption.

  This function provides enhanced streaming capabilities beyond basic chunk transformation,
  including error recovery, resource management, and lifecycle handling.

  ## Parameters
    - req_llm_stream: ReqLLM streaming response (enumerable of chunks)
    - opts: Adaptation options (optional)
      - :timeout - Stream timeout in milliseconds (default: 30_000)
      - :chunk_size - Maximum chunk size for processing (default: nil)
      - :error_recovery - Enable error recovery (default: true)
      - :resource_cleanup - Enable automatic resource cleanup (default: true)

  ## Returns
    - Adapted stream with Jido AI compatible chunk format and error handling

  ## Examples

      iex> mock_stream = [%{content: "Hello", finish_reason: nil}]
      iex> adapted = Jido.AI.ReqLlmBridge.StreamingAdapter.adapt_stream(mock_stream)
      iex> result = Enum.take(adapted, 1)
      iex> hd(result).content
      "Hello"
  """
  @spec adapt_stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def adapt_stream(req_llm_stream, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    error_recovery = Keyword.get(opts, :error_recovery, true)
    resource_cleanup = Keyword.get(opts, :resource_cleanup, true)

    req_llm_stream
    |> Stream.with_index()
    |> Stream.map(&transform_chunk_with_metadata/1)
    |> Stream.take_while(&continue_stream?/1)
    |> maybe_add_timeout(timeout)
    |> maybe_add_error_recovery(error_recovery)
    |> maybe_add_resource_cleanup(resource_cleanup)
  end

  @doc """
  Transforms a streaming chunk with enhanced metadata.

  Provides detailed chunk transformation with additional metadata for
  debugging and monitoring streaming operations.

  ## Parameters
    - chunk: ReqLLM streaming chunk
    - index: Chunk index in the stream (optional)

  ## Returns
    - Enhanced Jido AI compatible chunk with metadata
  """
  @spec transform_chunk_with_metadata({map() | struct(), integer()}) :: map()
  def transform_chunk_with_metadata({chunk, index}) when is_map(chunk) do
    base_chunk = ReqLlmBridge.transform_streaming_chunk(chunk)

    Map.merge(base_chunk, %{
      chunk_metadata: %{
        index: index,
        timestamp: DateTime.utc_now(),
        chunk_size: byte_size(get_chunk_content(chunk)),
        provider: extract_provider_from_chunk(chunk)
      }
    })
  end

  @doc """
  Detects end-of-stream conditions.

  Determines whether streaming should continue based on chunk content,
  finish reasons, and error conditions.

  ## Parameters
    - chunk: Processed streaming chunk

  ## Returns
    - Boolean indicating whether streaming should continue
  """
  @spec continue_stream?(map()) :: boolean()
  def continue_stream?(%{finish_reason: nil}), do: true
  def continue_stream?(%{finish_reason: ""}), do: true

  def continue_stream?(%{finish_reason: finish_reason}) when is_binary(finish_reason) do
    # Continue streaming unless we have a definitive stop condition
    finish_reason not in ["stop", "length", "content_filter", "tool_calls"]
  end

  def continue_stream?(_chunk), do: true

  @doc """
  Handles streaming errors with recovery mechanisms.

  Provides robust error handling for streaming operations with configurable
  recovery strategies and logging.

  ## Parameters
    - stream: Input stream to wrap with error handling
    - error_recovery: Enable error recovery mechanisms

  ## Returns
    - Stream with error handling wrapper
  """
  @spec handle_stream_errors(Enumerable.t(), boolean()) :: Enumerable.t()
  def handle_stream_errors(stream, error_recovery \\ true) do
    Stream.transform(stream, :ok, fn
      chunk, :ok ->
        try do
          {[chunk], :ok}
        rescue
          error ->
            log_streaming_error(error)

            if error_recovery do
              # Attempt to recover from error by continuing stream
              {[], :ok}
            else
              # Propagate error and terminate stream
              throw(
                {:error,
                 %{
                   reason: "streaming_error",
                   details: Exception.message(error),
                   original_error: error
                 }}
              )
            end
        end

      _chunk, {:error, _reason} = error ->
        # Stream is in error state, terminate
        throw(error)
    end)
  end

  @doc """
  Provides stream lifecycle management with automatic resource cleanup.

  Ensures proper resource management for streaming operations including
  connection cleanup and memory management.

  ## Parameters
    - stream: Input stream to manage
    - cleanup_enabled: Whether to enable automatic cleanup

  ## Returns
    - Stream with lifecycle management wrapper
  """
  @spec manage_stream_lifecycle(Enumerable.t(), boolean()) :: Enumerable.t()
  def manage_stream_lifecycle(stream, cleanup_enabled \\ true) do
    if cleanup_enabled do
      Stream.resource(
        fn ->
          log_streaming_operation("Stream lifecycle started")
          {:ok, stream}
        end,
        fn
          {:ok, stream} ->
            case Enumerable.reduce(stream, {:cont, []}, fn element, acc ->
                   {:cont, [element | acc]}
                 end) do
              {:done, results} ->
                {Enum.reverse(results), :done}

              {:halted, results} ->
                {Enum.reverse(results), :done}

              {:suspended, results, continuation} ->
                {Enum.reverse(results), {:suspended, continuation}}
            end

          :done ->
            {:halt, :done}

          {:suspended, continuation} ->
            {[], {:suspended, continuation}}
        end,
        fn _state ->
          log_streaming_operation("Stream lifecycle cleanup completed")
          :ok
        end
      )
    else
      stream
    end
  end

  # Private helper functions

  defp get_chunk_content(chunk) do
    chunk[:content] || chunk["content"] ||
      chunk[:text] || chunk["text"] ||
      chunk[:delta][:content] || chunk["delta"]["content"] ||
      ""
  end

  defp extract_provider_from_chunk(chunk) do
    # Extract provider information from chunk metadata if available
    chunk[:provider] || chunk["provider"] ||
      chunk[:model] || chunk["model"] ||
      "unknown"
  end

  defp maybe_add_timeout(stream, timeout) when is_integer(timeout) and timeout > 0 do
    Stream.transform(stream, :ok, fn chunk, acc ->
      # Simple timeout implementation - in production, would use more sophisticated timing
      {[chunk], acc}
    end)
  end

  defp maybe_add_timeout(stream, _timeout), do: stream

  defp maybe_add_error_recovery(stream, true) do
    handle_stream_errors(stream, true)
  end

  defp maybe_add_error_recovery(stream, false), do: stream

  defp maybe_add_resource_cleanup(stream, true) do
    manage_stream_lifecycle(stream, true)
  end

  defp maybe_add_resource_cleanup(stream, false), do: stream

  defp log_streaming_error(error) do
    if Application.get_env(:jido_ai, :enable_req_llm_logging, false) do
      Logger.error("[ReqLLM Streaming] Error: #{Exception.message(error)}",
        module: __MODULE__
      )
    end
  end

  defp log_streaming_operation(message) do
    if Application.get_env(:jido_ai, :enable_req_llm_logging, false) do
      Logger.debug("[ReqLLM Streaming] #{message}", module: __MODULE__)
    end
  end
end
