defmodule Jido.AI.Actions.ToolCalling.ExecuteTool do
  @moduledoc """
  A Jido.Action for direct tool execution without LLM involvement.

  This action executes a registered Action by name with the given parameters.
  It uses `Jido.AI.Turn` tool execution to keep result formatting consistent.

  ## Parameters

  * `tool_name` (required) - The name of the tool to execute
  * `params` (optional) - Parameters to pass to the tool (default: `%{}`)
  * `timeout` (optional) - Execution timeout in milliseconds (default: `30000`)

  ## Examples

      # Execute calculator tool
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ExecuteTool, %{
        tool_name: "calculator",
        params: %{"operation" => "add", "a" => 5, "b" => 3}
      })

      # Execute with timeout
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ExecuteTool, %{
        tool_name: "search",
        params: %{"query" => "Elixir programming"},
        timeout: 5000
      })
  """

  use Jido.Action,
    name: "tool_calling_execute_tool",
    description: "Execute a tool by name with parameters",
    category: "ai",
    tags: ["tool-calling", "execution", "tools"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        tool_name: Zoi.string(description: "The name of the tool to execute"),
        params:
          Zoi.map(description: "Parameters to pass to the tool")
          |> Zoi.default(%{})
          |> Zoi.optional(),
        timeout:
          Zoi.integer(description: "Execution timeout in milliseconds")
          |> Zoi.default(30_000)
          |> Zoi.optional()
      })

  alias Jido.AI.Turn

  @doc """
  Executes the tool by name.
  """
  @impl Jido.Action
  def run(params, context) do
    tool_name = params[:tool_name]
    tool_params = params[:params] || %{}
    timeout = params[:timeout] || 30_000

    with :ok <- validate_tool_name(tool_name),
         :ok <- validate_tool_params(tool_params),
         {:ok, result} <- execute_tool(tool_name, tool_params, timeout, context) do
      {:ok,
       %{
         tool_name: tool_name,
         result: result,
         status: :success
       }}
    end
  end

  # Private Functions

  defp validate_tool_name(nil), do: {:error, :tool_name_required}
  defp validate_tool_name(""), do: {:error, :tool_name_required}
  defp validate_tool_name(name) when is_binary(name), do: :ok
  defp validate_tool_name(_), do: {:error, :invalid_tool_name}

  defp validate_tool_params(params) when is_map(params), do: :ok
  defp validate_tool_params(_), do: {:error, :invalid_params_format}

  defp execute_tool(tool_name, params, timeout, context) do
    tool_call = %{id: "direct_tool_exec", name: tool_name, arguments: params}

    case Turn.run_tool_calls([tool_call], context, timeout: timeout) do
      {:ok, [%{raw_result: {:ok, result}}]} ->
        {:ok, format_result(result)}

      {:ok, [%{content: content, raw_result: {:error, _reason}}]} when is_binary(content) ->
        {:error, content}

      {:ok, [_]} ->
        {:error, "Tool execution failed"}

      {:ok, []} ->
        {:error, "Tool execution failed"}
    end
  end

  defp format_result(result) when is_binary(result), do: %{text: result}
  defp format_result(result) when is_map(result), do: result
  defp format_result(result) when is_list(result), do: %{items: result}
  defp format_result(result), do: %{value: result}
end
