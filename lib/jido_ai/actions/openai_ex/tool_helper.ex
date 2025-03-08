defmodule Jido.AI.Actions.OpenaiEx.ToolHelper do
  @moduledoc """
  Helper module for handling tool calling with OpenAiEx.
  Provides functions to convert Jido.Action to OpenAI tool format and handle tool responses.
  """

  require Logger

  @doc """
  Converts a list of Jido.Action modules to OpenAI tool format.
  Each action must implement the Jido.Action.Tool protocol.

  ## Parameters
    - actions: List of Jido.Action modules that implement Jido.Action.Tool

  ## Returns
    - {:ok, tools} where tools is a list of OpenAI tool specifications
    - {:error, reason} if any action doesn't implement the protocol
  """
  @spec to_openai_tools([module()]) :: {:ok, list(map())} | {:error, term()}
  def to_openai_tools(actions) when is_list(actions) do
    tools =
      Enum.map(actions, fn action ->
        if function_exported?(action, :to_tool, 0) do
          case action.to_tool() do
            %{name: name, description: description, parameters_schema: schema} ->
              %{
                type: "function",
                function: %{
                  name: name,
                  description: description,
                  parameters: schema
                }
              }

            _ ->
              {:error, "Action #{inspect(action)} does not implement Jido.Action.Tool protocol"}
          end
        else
          {:error, "Action #{inspect(action)} does not implement Jido.Action.Tool protocol"}
        end
      end)

    case tools do
      [error] when is_tuple(error) and elem(error, 0) == :error ->
        error

      _ ->
        if Enum.any?(tools, &match?({:error, _}, &1)) do
          {:error, "One or more actions failed to convert to tools"}
        else
          {:ok, tools}
        end
    end
  end

  @doc """
  Handles a tool call response from OpenAI.
  Executes the appropriate action with the given parameters.

  ## Parameters
    - tool_call: The tool call object from OpenAI response
    - available_actions: List of available Jido.Action modules

  ## Returns
    - {:ok, result} where result is the output of the action
    - {:error, reason} if the tool call cannot be handled
  """
  @spec handle_tool_call(map(), [module()]) :: {:ok, term()} | {:error, term()}
  def handle_tool_call(%{name: name, arguments: arguments} = _tool_call, available_actions) do
    with {:ok, arguments} <- Jason.decode(arguments),
         {:ok, action} <- find_action(name, available_actions),
         {:ok, params} <- convert_params(arguments, action),
         {:ok, result} <- execute_action(action, params) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Failed to handle tool call: #{inspect(error)}"}
    end
  end

  def handle_tool_call(_tool_call, _available_actions) do
    {:error, "Invalid tool call format"}
  end

  @doc """
  Processes a chat completion response that may contain tool calls.
  If tool calls are present, executes them and returns the results.

  ## Parameters
    - response: The chat completion response from OpenAI
    - available_actions: List of available Jido.Action modules

  ## Returns
    - {:ok, %{content: content, tool_results: results}} where content is the assistant's message
      and results are the outputs of any tool calls
    - {:error, reason} if tool calls cannot be processed
  """
  @spec process_response(map(), [module()]) :: {:ok, map()} | {:error, term()}
  def process_response(%{choices: [%{message: message} | _]} = _response, available_actions) do
    case message do
      %{tool_calls: tool_calls} when is_list(tool_calls) ->
        results =
          Enum.map(tool_calls, fn tool_call ->
            case handle_tool_call(tool_call, available_actions) do
              {:ok, result} -> {:ok, %{tool: tool_call.name, result: result}}
              error -> error
            end
          end)

        if Enum.any?(results, &match?({:error, _}, &1)) do
          {:error, "One or more tool calls failed"}
        else
          {:ok,
           %{
             content: message.content,
             tool_results: Enum.map(results, fn {:ok, result} -> result end)
           }}
        end

      %{content: content} ->
        {:ok, %{content: content, tool_results: []}}

      _ ->
        {:error, "Invalid message format in response"}
    end
  end

  def process_response(_response, _available_actions) do
    {:error, "Invalid response format"}
  end

  # Private functions

  defp find_action(name, available_actions) do
    case Enum.find(available_actions, fn action ->
           case action.to_tool() do
             %{name: ^name} -> true
             _ -> false
           end
         end) do
      nil -> {:error, "No action found for tool: #{name}"}
      action -> {:ok, action}
    end
  end

  defp convert_params(params, action) do
    case action do
      Jido.Actions.Arithmetic.Add ->
        with {:ok, value} <- parse_integer(params["value"]),
             {:ok, amount} <- parse_integer(params["amount"]) do
          {:ok, %{value: value, amount: amount}}
        end

      _ ->
        # For other actions, convert string keys to atoms
        {:ok, Map.new(params, fn {k, v} -> {String.to_atom(k), v} end)}
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid integer: #{value}"}
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp execute_action(action, params) do
    case action.run(params, %{}) do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      error -> {:error, "Action execution failed: #{inspect(error)}"}
    end
  end
end
