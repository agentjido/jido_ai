defmodule Jido.AI.ReqLlmBridge.ResponseAggregator do
  @moduledoc """
  Aggregates and formats responses from LLM interactions with tool calls.

  This module takes raw LLM responses, tool execution results, and conversation
  context to produce a unified, well-formatted response for the end user. It
  handles the complexity of combining text content with tool results and
  provides consistent response formatting across different interaction types.

  ## Features

  - Response content aggregation from multiple sources
  - Tool result integration and formatting
  - Usage statistics compilation
  - Error result handling and user-friendly formatting
  - Streaming response aggregation
  - Response metadata enrichment

  ## Response Format

  The aggregated response follows a consistent structure:

      %{
        content: "Final response content with tool results integrated",
        tool_calls: [%{id: "call_1", function: %{name: "tool", arguments: %{}}}],
        tool_results: [%{tool_call_id: "call_1", content: "result"}],
        usage: %{prompt_tokens: 50, completion_tokens: 25, total_tokens: 75},
        conversation_id: "conv_123",
        finished: true,
        metadata: %{processing_time_ms: 1250, tools_executed: 2}
      }

  ## Usage

      {:ok, aggregated} = ResponseAggregator.aggregate_response(
        llm_response_with_tools,
        context
      )

      IO.puts(aggregated.content)
      # "Based on the weather data, it's sunny in Paris with 22°C."
  """

  require Logger
  alias Jido.AI.ReqLlmBridge.ErrorHandler

  @type response_context :: %{
          conversation_id: String.t(),
          processing_start_time: integer(),
          options: map()
        }

  @type aggregated_response :: %{
          content: String.t(),
          tool_calls: [map()],
          tool_results: [map()],
          usage: map(),
          conversation_id: String.t(),
          finished: boolean(),
          metadata: map()
        }

  @doc """
  Aggregates a complete response including tool results.

  Takes the LLM response with executed tool results and combines them
  into a single, coherent response for the user.

  ## Parameters

  - `response_with_tools` - LLM response enhanced with tool execution results
  - `context` - Processing context with conversation ID and options

  ## Returns

  - `{:ok, aggregated_response}` - Successfully aggregated response
  - `{:error, reason}` - Error during aggregation

  ## Examples

      {:ok, final_response} = ResponseAggregator.aggregate_response(
        %{
          content: "I'll check the weather for you.",
          tool_calls: [weather_call],
          tool_results: [weather_result],
          usage: %{total_tokens: 75}
        },
        %{conversation_id: "conv_123", options: %{}}
      )
  """
  @spec aggregate_response(map(), response_context()) ::
          {:ok, aggregated_response()} | {:error, term()}
  def aggregate_response(response_with_tools, context) do
    start_time = Map.get(context, :processing_start_time, System.monotonic_time(:millisecond))

    try do
      aggregated = %{
        content: build_final_content(response_with_tools),
        tool_calls: extract_tool_calls(response_with_tools),
        tool_results: extract_tool_results(response_with_tools),
        usage: extract_usage_stats(response_with_tools),
        conversation_id: context.conversation_id,
        finished: determine_if_finished(response_with_tools),
        metadata: build_response_metadata(response_with_tools, context, start_time)
      }

      {:ok, aggregated}
    rescue
      error ->
        Logger.error("Response aggregation failed: #{inspect(error)}")
        {:error, {:aggregation_failed, error}}
    end
  end

  @doc """
  Aggregates a streaming response incrementally.

  Handles streaming responses by accumulating content and tool results
  as they arrive, providing partial results during processing.

  ## Parameters

  - `stream_chunks` - Enumerable of response chunks
  - `context` - Processing context

  ## Returns

  - `{:ok, final_response}` - Complete aggregated response
  - `{:error, reason}` - Error during streaming aggregation

  ## Examples

      {:ok, response} = ResponseAggregator.aggregate_streaming_response(
        response_stream,
        context
      )
  """
  @spec aggregate_streaming_response(Enumerable.t(), response_context()) ::
          {:ok, aggregated_response()} | {:error, term()}
  def aggregate_streaming_response(stream_chunks, context) do
    _start_time = Map.get(context, :processing_start_time, System.monotonic_time(:millisecond))

    try do
      {accumulated_content, tool_data, usage_data} =
        Enum.reduce(stream_chunks, {"", [], %{}}, fn
          # Skip nil chunks
          nil, acc ->
            acc

          # Process valid chunks
          chunk, {content, tools, usage} ->
            chunk_content = extract_chunk_content(chunk)
            chunk_tools = extract_chunk_tools(chunk)
            chunk_usage = extract_chunk_usage(chunk)

            {
              content <> chunk_content,
              tools ++ chunk_tools,
              merge_usage_stats(usage, chunk_usage)
            }
        end)

      response_data = %{
        content: accumulated_content,
        tool_calls: extract_unique_tool_calls(tool_data),
        tool_results: extract_tool_results_from_chunks(tool_data),
        usage: usage_data,
        finished: true
      }

      aggregate_response(response_data, context)
    rescue
      error ->
        Logger.error("Streaming aggregation failed: #{inspect(error)}")
        {:error, {:streaming_aggregation_failed, error}}
    end
  end

  @doc """
  Formats a response for human consumption.

  Takes an aggregated response and formats it in a user-friendly way,
  integrating tool results into the narrative and handling errors gracefully.

  ## Parameters

  - `aggregated_response` - Response from aggregate_response/2
  - `format_options` - Options for formatting (e.g., include_metadata)

  ## Returns

  - Formatted string suitable for display to users

  ## Examples

      iex> alias Jido.AI.ReqLlmBridge.ResponseAggregator
      iex> response = %{
      ...>   content: "The weather is",
      ...>   tool_calls: [],
      ...>   tool_results: [%{content: "sunny, 22°C"}],
      ...>   usage: %{total_tokens: 50},
      ...>   conversation_id: "conv_123",
      ...>   finished: true,
      ...>   metadata: %{processing_time_ms: 100}
      ...> }
      iex> ResponseAggregator.format_for_user(response, %{tool_result_style: :integrated})
      "The weather is\\n\\nBased on the tool result: sunny, 22°C"

      iex> alias Jido.AI.ReqLlmBridge.ResponseAggregator
      iex> response = %{
      ...>   content: "Hello!",
      ...>   tool_calls: [],
      ...>   tool_results: [],
      ...>   usage: %{total_tokens: 10},
      ...>   conversation_id: "conv_456",
      ...>   finished: true,
      ...>   metadata: %{processing_time_ms: 50}
      ...> }
      iex> ResponseAggregator.format_for_user(response)
      "Hello!"
  """
  @spec format_for_user(aggregated_response(), map()) :: String.t()
  def format_for_user(aggregated_response, format_options \\ %{}) do
    base_content = aggregated_response.content
    tool_results = aggregated_response.tool_results
    include_metadata = Map.get(format_options, :include_metadata, false)
    tool_style = Map.get(format_options, :tool_result_style, :integrated)

    formatted_content =
      case tool_style do
        :integrated -> integrate_tool_results_into_content(base_content, tool_results)
        :appended -> append_tool_results_to_content(base_content, tool_results)
        :separate -> base_content
      end

    if include_metadata do
      add_metadata_to_formatted_content(formatted_content, aggregated_response)
    else
      formatted_content
    end
  end

  @doc """
  Extracts key metrics from an aggregated response.

  Provides analytics data about the response including token usage,
  processing time, tool execution statistics, and success rates.

  ## Parameters

  - `aggregated_response` - Response to extract metrics from

  ## Returns

  - Map containing various metrics and statistics

  ## Examples

      iex> alias Jido.AI.ReqLlmBridge.ResponseAggregator
      iex> response = %{
      ...>   content: "Result",
      ...>   tool_calls: [],
      ...>   tool_results: [%{content: "success"}, %{content: "ok", error: false}],
      ...>   usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30},
      ...>   conversation_id: "conv_789",
      ...>   finished: true,
      ...>   metadata: %{processing_time_ms: 150}
      ...> }
      iex> metrics = ResponseAggregator.extract_metrics(response)
      iex> metrics.total_tokens
      30
      iex> metrics.tools_executed
      2
      iex> metrics.tools_successful
      2
      iex> metrics.tool_success_rate
      100.0

      iex> alias Jido.AI.ReqLlmBridge.ResponseAggregator
      iex> response = %{
      ...>   content: "Error occurred",
      ...>   tool_calls: [],
      ...>   tool_results: [%{content: "failed", error: true}],
      ...>   usage: %{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15},
      ...>   conversation_id: "conv_err",
      ...>   finished: true,
      ...>   metadata: %{processing_time_ms: 75}
      ...> }
      iex> metrics = ResponseAggregator.extract_metrics(response)
      iex> metrics.tools_failed
      1
      iex> metrics.tool_success_rate
      0.0
  """
  @spec extract_metrics(aggregated_response()) :: map()
  def extract_metrics(aggregated_response) do
    metadata = aggregated_response.metadata
    usage = aggregated_response.usage
    tool_results = aggregated_response.tool_results

    successful_tools =
      Enum.count(tool_results, fn result ->
        not Map.get(result, :error, false)
      end)

    failed_tools =
      Enum.count(tool_results, fn result ->
        Map.get(result, :error, false)
      end)

    %{
      processing_time_ms: Map.get(metadata, :processing_time_ms, 0),
      total_tokens: Map.get(usage, :total_tokens, 0),
      prompt_tokens: Map.get(usage, :prompt_tokens, 0),
      completion_tokens: Map.get(usage, :completion_tokens, 0),
      tools_executed: length(tool_results),
      tools_successful: successful_tools,
      tools_failed: failed_tools,
      tool_success_rate: calculate_success_rate(successful_tools, length(tool_results)),
      conversation_id: aggregated_response.conversation_id,
      finished: aggregated_response.finished
    }
  end

  # Private Functions

  defp build_final_content(response) do
    base_content = extract_base_content(response)
    tool_results = extract_tool_results(response)

    case {base_content, tool_results} do
      {"", []} ->
        "I don't have any response to provide."

      {content, []} ->
        content

      {"", tool_results} ->
        format_tool_only_response(tool_results)

      {content, _tool_results} ->
        # Keep original content - tool results will be added in format_for_user if needed
        content
    end
  end

  defp extract_base_content(response) do
    content = Map.get(response, :content, Map.get(response, "content", ""))

    cond do
      is_binary(content) -> String.trim(content)
      is_list(content) -> extract_text_from_content_list(content)
      true -> to_string(content)
    end
  end

  defp extract_text_from_content_list(content_list) do
    content_list
    |> Enum.map_join("", &extract_text_from_content_item/1)
    |> String.trim()
  end

  defp extract_text_from_content_item(%{type: "text", text: text}), do: text
  defp extract_text_from_content_item(%{"type" => "text", "text" => text}), do: text
  defp extract_text_from_content_item(text) when is_binary(text), do: text
  defp extract_text_from_content_item(_), do: ""

  defp extract_tool_calls(response) do
    Map.get(response, :tool_calls, Map.get(response, "tool_calls", []))
  end

  defp extract_tool_results(response) do
    Map.get(response, :tool_results, Map.get(response, "tool_results", []))
  end

  defp extract_usage_stats(response) do
    default_usage = %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
    Map.get(response, :usage, Map.get(response, "usage", default_usage))
  end

  defp determine_if_finished(response) do
    # Response is finished if there are no pending tool calls that need execution
    tool_calls = extract_tool_calls(response)
    tool_results = extract_tool_results(response)

    # If we have tool calls but no results, we might need another round
    executed_call_ids =
      MapSet.new(tool_results, fn result ->
        Map.get(result, :tool_call_id, Map.get(result, "tool_call_id"))
      end)

    pending_call_ids =
      MapSet.new(tool_calls, fn call ->
        Map.get(call, :id, Map.get(call, "id"))
      end)

    MapSet.subset?(pending_call_ids, executed_call_ids)
  end

  defp build_response_metadata(response, _context, start_time) do
    end_time = System.monotonic_time(:millisecond)
    processing_time = end_time - start_time

    base_metadata = %{
      processing_time_ms: processing_time,
      tools_executed: length(extract_tool_results(response)),
      has_tool_calls: not Enum.empty?(extract_tool_calls(response)),
      response_type: determine_response_type(response)
    }

    # Include any errors that occurred during tool execution
    tool_errors = extract_tool_errors(response)

    if Enum.empty?(tool_errors) do
      base_metadata
    else
      Map.put(base_metadata, :tool_errors, tool_errors)
    end
  end

  defp determine_response_type(response) do
    has_content = String.length(extract_base_content(response)) > 0
    has_tools = not Enum.empty?(extract_tool_results(response))

    case {has_content, has_tools} do
      {true, true} -> :content_with_tools
      {true, false} -> :content_only
      {false, true} -> :tools_only
      {false, false} -> :empty
    end
  end

  defp extract_tool_errors(response) do
    response
    |> extract_tool_results()
    |> Enum.filter(fn result -> Map.get(result, :error, false) end)
    |> Enum.map(fn result ->
      ErrorHandler.sanitize_error_for_logging(result)
    end)
  end

  defp format_tool_only_response(tool_results) do
    successful_results =
      Enum.filter(tool_results, fn result ->
        not Map.get(result, :error, false)
      end)

    case successful_results do
      [] ->
        "I attempted to use tools to help with your request, but encountered errors. Please try again."

      results ->
        formatted_results = Enum.map(results, &format_single_tool_result/1)
        "Here are the results:\n\n" <> Enum.join(formatted_results, "\n\n")
    end
  end

  defp format_single_tool_result(result) do
    tool_name = Map.get(result, :name, "Tool")
    content = Map.get(result, :content, "")

    case Jason.decode(content) do
      {:ok, parsed_content} when is_map(parsed_content) ->
        format_structured_tool_result(tool_name, parsed_content)

      {:ok, parsed_content} ->
        "#{tool_name}: #{inspect(parsed_content)}"

      {:error, _} ->
        "#{tool_name}: #{content}"
    end
  end

  defp format_structured_tool_result(tool_name, content) when is_map(content) do
    formatted_fields =
      content
      |> Enum.map_join("\n", fn {key, value} -> "  #{key}: #{inspect(value)}" end)

    "#{tool_name} results:\n#{formatted_fields}"
  end

  defp integrate_tool_results_into_content(content, tool_results) do
    successful_results =
      Enum.filter(tool_results, fn result ->
        not Map.get(result, :error, false)
      end)

    case successful_results do
      [] -> content
      [single_result] -> integrate_single_tool_result(content, single_result)
      multiple_results -> integrate_multiple_tool_results(content, multiple_results)
    end
  end

  defp integrate_single_tool_result(content, result) do
    tool_content = extract_tool_result_content(result)

    if String.contains?(String.downcase(content), ["based on", "according to", "the result"]) do
      content
    else
      "#{content}\n\nBased on the tool result: #{tool_content}"
    end
  end

  defp integrate_multiple_tool_results(content, results) do
    tool_summary =
      results
      |> Enum.map_join("; ", &extract_tool_result_content/1)

    "#{content}\n\nBased on the tool results: #{tool_summary}"
  end

  defp extract_tool_result_content(result) do
    content = Map.get(result, :content, "")

    case Jason.decode(content) do
      {:ok, parsed} when is_map(parsed) ->
        # Extract the most relevant information from structured data
        extract_key_information(parsed)

      {:ok, parsed} ->
        to_string(parsed)

      {:error, _} ->
        content
    end
  end

  defp extract_key_information(data) when is_map(data) do
    # Try to find the most relevant field to display
    priority_keys = ["result", "answer", "value", "message", "summary", "description"]

    key =
      Enum.find(priority_keys, fn k ->
        Map.has_key?(data, k) or Map.has_key?(data, String.to_atom(k))
      end)

    cond do
      key && Map.has_key?(data, key) -> to_string(data[key])
      key && Map.has_key?(data, String.to_atom(key)) -> to_string(data[String.to_atom(key)])
      true -> inspect(data)
    end
  end

  defp append_tool_results_to_content(content, tool_results) do
    successful_results =
      Enum.filter(tool_results, fn result ->
        not Map.get(result, :error, false)
      end)

    case successful_results do
      [] ->
        content

      results ->
        formatted_results = Enum.map(results, &format_single_tool_result/1)
        content <> "\n\n---\n\nTool Results:\n" <> Enum.join(formatted_results, "\n")
    end
  end

  defp add_metadata_to_formatted_content(content, response) do
    metadata = response.metadata
    usage = response.usage

    metadata_lines = [
      "Processing time: #{metadata.processing_time_ms}ms",
      "Tokens used: #{usage.total_tokens}",
      "Tools executed: #{metadata.tools_executed}"
    ]

    content <> "\n\n---\nResponse Metadata:\n" <> Enum.join(metadata_lines, "\n")
  end

  defp calculate_success_rate(successful, total) when total > 0 do
    Float.round(successful / total * 100, 1)
  end

  defp calculate_success_rate(_successful, 0), do: 0.0

  defp extract_chunk_content(chunk) do
    Map.get(chunk, :content, Map.get(chunk, "content", ""))
  end

  defp extract_chunk_tools(chunk) do
    Map.get(chunk, :tool_calls, Map.get(chunk, "tool_calls", []))
  end

  defp extract_chunk_usage(chunk) do
    Map.get(chunk, :usage, Map.get(chunk, "usage", %{}))
  end

  defp merge_usage_stats(usage1, usage2) do
    %{
      prompt_tokens: Map.get(usage1, :prompt_tokens, 0) + Map.get(usage2, :prompt_tokens, 0),
      completion_tokens:
        Map.get(usage1, :completion_tokens, 0) + Map.get(usage2, :completion_tokens, 0),
      total_tokens: Map.get(usage1, :total_tokens, 0) + Map.get(usage2, :total_tokens, 0)
    }
  end

  defp extract_unique_tool_calls(tool_data) do
    tool_data
    |> List.flatten()
    |> Enum.uniq_by(fn call -> Map.get(call, :id, Map.get(call, "id")) end)
  end

  defp extract_tool_results_from_chunks(_tool_data) do
    # In streaming, tool results might come in the stream or be generated separately
    # This is a simplified implementation
    []
  end
end
