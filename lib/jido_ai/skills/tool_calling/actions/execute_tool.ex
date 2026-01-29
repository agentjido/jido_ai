defmodule Jido.AI.Skills.ToolCalling.Actions.ExecuteTool do
  @moduledoc """
  A Jido.Action for direct tool execution without LLM involvement.

  This action executes a registered Action by name with the given parameters.
  It uses `Jido.AI.Tools.Executor` for execution.

  ## Parameters

  * `tool_name` (required) - The name of the tool to execute
  * `params` (optional) - Parameters to pass to the tool (default: `%{}`)
  * `timeout` (optional) - Execution timeout in milliseconds (default: `30000`)

  ## Examples

      # Execute calculator tool
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ExecuteTool, %{
        tool_name: "calculator",
        params: %{"operation" => "add", "a" => 5, "b" => 3}
      })

      # Execute with timeout
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ExecuteTool, %{
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

  alias Jido.AI.Tools.Executor

  @doc """
  Executes the tool by name.
  """
  @impl Jido.Action
  def run(params, _context) do
    tool_name = params[:tool_name]
    tool_params = params[:params] || %{}
    timeout = params[:timeout] || 30_000

    with :ok <- validate_tool_name(tool_name),
         :ok <- validate_tool_params(tool_params),
         {:ok, result} <- execute_tool(tool_name, tool_params, timeout) do
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

  defp execute_tool(tool_name, params, timeout) do
    case Executor.execute(tool_name, params, %{}, timeout: timeout) do
      {:ok, result} ->
        {:ok, format_result(result)}

      {:error, error} when is_map(error) ->
        {:error, Map.get(error, :error, "Tool execution failed")}
    end
  end

  defp format_result(result) when is_binary(result), do: %{text: result}
  defp format_result(result) when is_map(result), do: result
  defp format_result(result) when is_list(result), do: %{items: result}
  defp format_result(result), do: %{value: result}
end
