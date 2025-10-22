defmodule Jido.AI.ReqLlmBridge.ToolResponseHandler do
  @moduledoc """
  Handles processing of LLM responses that may contain tool calls.

  This module processes responses from LLM requests and handles any tool calls
  that need to be executed. It coordinates tool execution, aggregates results,
  and formats the final response for the user.

  ## Features

  - Tool call detection and extraction from LLM responses
  - Automatic tool execution with error handling
  - Multi-turn tool calling support (tools that call other tools)
  - Response aggregation and formatting
  - Streaming response handling with incremental tool calls
  - Tool execution timeout and circuit breaker support

  ## Response Flow

  1. LLM returns response with potential tool calls
  2. Extract and validate tool call parameters
  3. Execute tools using ToolExecutor
  4. Aggregate tool results
  5. Send tool results back to LLM if needed
  6. Return final formatted response

  ## Error Handling

  - Individual tool failures don't stop the entire response
  - Tool execution timeouts are handled gracefully
  - Malformed tool calls are logged and skipped
  - Circuit breaker prevents cascade failures
  """

  alias Jido.AI.ReqLlmBridge.{ConversationManager, ErrorHandler, ResponseAggregator, ToolExecutor}
  require Logger

  @tool_execution_timeout 30_000

  @type tool_call :: %{
          id: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t() | map()
          }
        }

  @type tool_result :: %{
          tool_call_id: String.t(),
          role: String.t(),
          content: String.t()
        }

  @type response_context :: %{
          conversation_id: String.t(),
          max_tool_calls: pos_integer(),
          timeout: pos_integer(),
          context: map()
        }

  @doc """
  Processes a complete LLM response and executes any tool calls.

  Takes the raw LLM response, extracts tool calls, executes them,
  and returns a formatted response with results.

  ## Parameters

  - `llm_response` - Raw response from the LLM
  - `conversation_id` - Conversation context identifier
  - `options` - Processing options including timeouts and limits

  ## Returns

  - `{:ok, processed_response}` - Successfully processed response
  - `{:error, reason}` - Error during processing or tool execution

  ## Examples

      {:ok, response} = ToolResponseHandler.process_llm_response(
        llm_response,
        conversation_id,
        %{max_tool_calls: 5, timeout: 30_000}
      )
  """
  @spec process_llm_response(map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def process_llm_response(llm_response, conversation_id, options) do
    context = build_response_context(conversation_id, options)

    with {:ok, tool_calls} <- extract_tool_calls(llm_response),
         {:ok, response_with_tools} <-
           execute_tool_calls_if_present(
             llm_response,
             tool_calls,
             context
           ),
         {:ok, final_response} <-
           ResponseAggregator.aggregate_response(
             response_with_tools,
             context
           ) do
      {:ok, final_response}
    else
      {:error, reason} ->
        log_processing_error(reason, conversation_id)
        {:error, {:response_processing_failed, reason}}
    end
  end

  @doc """
  Processes a streaming LLM response with incremental tool calls.

  Handles streaming responses where tool calls may arrive incrementally
  across multiple chunks. Buffers partial tool calls until complete,
  then executes them.

  ## Parameters

  - `stream` - Stream of response chunks from the LLM
  - `conversation_id` - Conversation context identifier
  - `options` - Processing options

  ## Returns

  - `{:ok, final_response}` - Complete processed response
  - `{:error, reason}` - Error during streaming or processing

  ## Examples

      {:ok, response} = ToolResponseHandler.process_streaming_response(
        response_stream,
        conversation_id,
        %{timeout: 60_000}
      )
  """
  @spec process_streaming_response(Enumerable.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def process_streaming_response(stream, conversation_id, options) do
    context = build_response_context(conversation_id, options)

    try do
      {accumulated_response, tool_calls} = accumulate_streaming_response(stream, context)

      with {:ok, response_with_tools} <-
             execute_tool_calls_if_present(
               accumulated_response,
               tool_calls,
               context
             ) do
        ResponseAggregator.aggregate_response(
          response_with_tools,
          context
        )
      end
    rescue
      error ->
        log_streaming_error(error, conversation_id)
        {:error, {:streaming_processing_failed, error}}
    end
  end

  @doc """
  Executes a list of tool calls and returns their results.

  This function can be used independently to execute tool calls
  without going through the full response processing pipeline.

  ## Parameters

  - `tool_calls` - List of tool call descriptions
  - `context` - Execution context with conversation and options

  ## Returns

  - `{:ok, tool_results}` - List of tool execution results
  - `{:error, reason}` - Error during tool execution

  ## Examples

      tool_calls = [
        %{
          id: "call_1",
          function: %{name: "weather", arguments: %{"location" => "Paris"}}
        }
      ]

      {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)
  """
  @spec execute_tool_calls([tool_call()], response_context()) ::
          {:ok, [tool_result()]} | {:error, term()}
  def execute_tool_calls(tool_calls, context) do
    timeout = Map.get(context, :timeout, @tool_execution_timeout)
    max_calls = Map.get(context, :max_tool_calls, length(tool_calls))

    limited_calls = Enum.take(tool_calls, max_calls)

    results =
      limited_calls
      |> Task.async_stream(
        fn tool_call -> execute_single_tool_call(tool_call, context) end,
        timeout: timeout,
        on_timeout: :kill_task,
        max_concurrency: 4
      )
      |> Enum.map(&handle_tool_execution_result/1)

    successful_results =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    {:ok, successful_results}
  rescue
    error ->
      Logger.error("Tool execution failed: #{inspect(error)}")
      {:error, {:tool_execution_failed, error}}
  end

  # Private Functions

  defp build_response_context(conversation_id, options) do
    %{
      conversation_id: conversation_id,
      max_tool_calls: Map.get(options, :max_tool_calls, 5),
      timeout: Map.get(options, :timeout, @tool_execution_timeout),
      context: Map.get(options, :context, %{})
    }
  end

  defp extract_tool_calls(%{tool_calls: tool_calls}) when is_list(tool_calls) do
    {:ok, tool_calls}
  end

  defp extract_tool_calls(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    {:ok, tool_calls}
  end

  defp extract_tool_calls(_response) do
    {:ok, []}
  end

  defp execute_tool_calls_if_present(response, [], _context) do
    {:ok, response}
  end

  defp execute_tool_calls_if_present(response, tool_calls, context) do
    case execute_tool_calls(tool_calls, context) do
      {:ok, tool_results} ->
        enhanced_response =
          response
          |> Map.put(:tool_results, tool_results)
          |> Map.put(:has_tool_calls, true)

        {:ok, enhanced_response}

      {:error, reason} ->
        Logger.warning("Some tools failed to execute: #{inspect(reason)}")

        # Continue with partial results rather than failing completely
        enhanced_response =
          response
          |> Map.put(:tool_results, [])
          |> Map.put(:tool_execution_errors, [reason])
          |> Map.put(:has_tool_calls, true)

        {:ok, enhanced_response}
    end
  end

  defp execute_single_tool_call(tool_call, context) do
    %{id: call_id, function: function} = tool_call
    %{name: function_name, arguments: arguments} = function

    with {:ok, tool_module} <- resolve_tool_module(function_name, context),
         {:ok, parsed_args} <- parse_tool_arguments(arguments),
         {:ok, result} <-
           ToolExecutor.execute_tool(
             tool_module,
             parsed_args,
             context.context,
             context.timeout
           ) do
      format_tool_result(call_id, function_name, result)
    else
      {:error, reason} ->
        format_tool_error(call_id, function_name, reason)
    end
  end

  defp resolve_tool_module(function_name, context) do
    case ConversationManager.find_tool_by_name(context.conversation_id, function_name) do
      {:ok, tool_descriptor} -> {:ok, tool_descriptor.action_module}
      {:error, :not_found} -> {:error, {:tool_not_found, function_name}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:argument_parsing_failed, reason}}
    end
  end

  defp parse_tool_arguments(arguments) when is_map(arguments) do
    {:ok, arguments}
  end

  defp parse_tool_arguments(arguments) do
    {:error, {:invalid_arguments_format, arguments}}
  end

  defp format_tool_result(call_id, function_name, result) do
    content =
      case Jason.encode(result) do
        {:ok, json} -> json
        {:error, _} -> inspect(result)
      end

    {:ok,
     %{
       tool_call_id: call_id,
       role: "tool",
       name: function_name,
       content: content
     }}
  end

  defp format_tool_error(call_id, function_name, error) do
    sanitized_error = ErrorHandler.sanitize_error_for_logging(error)

    error_content = %{
      error: true,
      type: "tool_execution_error",
      message: "Tool execution failed",
      details: sanitized_error
    }

    content =
      case Jason.encode(error_content) do
        {:ok, json} -> json
        {:error, _} -> inspect(error_content)
      end

    {:ok,
     %{
       tool_call_id: call_id,
       role: "tool",
       name: function_name,
       content: content,
       error: true
     }}
  end

  defp handle_tool_execution_result({:ok, result}), do: result

  defp handle_tool_execution_result({:exit, :timeout}) do
    {:error, {:tool_timeout, "Tool execution timed out"}}
  end

  defp handle_tool_execution_result({:exit, reason}) do
    {:error, {:tool_exit, reason}}
  end

  defp accumulate_streaming_response(stream, _context) do
    Enum.reduce(stream, {%{content: ""}, []}, fn chunk, {acc_response, acc_tools} ->
      case process_stream_chunk(chunk, acc_response, acc_tools) do
        {:ok, updated_response, updated_tools} ->
          {updated_response, updated_tools}
      end
    end)
  end

  defp process_stream_chunk(chunk, accumulated_response, accumulated_tools) do
    content = Map.get(chunk, :content, Map.get(chunk, "content", ""))
    tool_calls = Map.get(chunk, :tool_calls, Map.get(chunk, "tool_calls", []))

    updated_response =
      accumulated_response
      |> Map.update(:content, content, &(&1 <> content))

    updated_tools = accumulated_tools ++ tool_calls

    {:ok, updated_response, updated_tools}
  end

  defp log_processing_error(error, conversation_id) do
    sanitized_error = ErrorHandler.sanitize_error_for_logging(error)

    Logger.error("Response processing failed",
      conversation_id: conversation_id,
      error: sanitized_error
    )
  end

  defp log_streaming_error(error, conversation_id) do
    sanitized_error = ErrorHandler.sanitize_error_for_logging(error)

    Logger.error("Streaming response processing failed",
      conversation_id: conversation_id,
      error: sanitized_error
    )
  end
end
