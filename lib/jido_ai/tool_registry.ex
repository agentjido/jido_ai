defmodule Jido.AI.ToolRegistry do
  @moduledoc """
  Resolves trusted model tool names to Jido Action modules.
  """

  @tools %{
    "add" => %{action: Jido.AI.Tools.Add, description: "Add two numbers."},
    "multiply" => %{
      action: Jido.AI.Tools.Multiply,
      description: "Multiply two numbers."
    }
  }

  @tool_names @tools |> Map.keys() |> Enum.sort()

  @doc "Returns the names that the Agent can expose to a model."
  @spec names() :: [String.t()]
  def names, do: @tool_names

  @doc "Builds ReqLLM definitions for a selected set of trusted tools."
  @spec definitions([String.t()]) :: {:ok, [ReqLLM.Tool.t()]} | {:error, term()}
  def definitions(names) when is_list(names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, tools} ->
      case definition(name) do
        {:ok, tool} -> {:cont, {:ok, [tool | tools]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tools} -> {:ok, Enum.reverse(tools)}
      error -> error
    end
  end

  @doc "Validates one portable model tool call without executing it."
  @spec validate_call(map()) :: :ok | {:error, term()}
  def validate_call(call) do
    with {:ok, _resolved} <- resolve_call(call), do: :ok
  end

  @doc "Resolves and validates one portable model call for graph construction."
  @spec resolve_call(map()) ::
          {:ok,
           %{
             id: String.t(),
             name: String.t(),
             action: module(),
             params: map()
           }}
          | {:error, term()}
  def resolve_call(%{id: id, name: name, arguments: arguments})
      when is_binary(id) and id != "" and is_binary(name) and is_map(arguments) do
    with {:ok, tool} <- fetch(name),
         {:ok, params} <- decode_arguments(tool.action, arguments) do
      {:ok, %{id: id, name: name, action: tool.action, params: params}}
    end
  end

  def resolve_call(%{name: name}) when is_binary(name), do: {:error, {:unknown_tool, name}}
  def resolve_call(_call), do: {:error, :invalid_tool_call}

  @doc false
  @spec execution_boundary(map()) :: {:error, atom()}
  def execution_boundary(_arguments), do: {:error, :tool_must_run_in_agent_graph}

  defp definition(name) do
    with {:ok, tool} <- fetch(name) do
      ReqLLM.Tool.new(
        name: name,
        description: tool.description,
        parameter_schema: tool.action.schema(),
        callback: {__MODULE__, :execution_boundary},
        strict: true
      )
    end
  end

  defp fetch(name) do
    case Map.fetch(@tools, name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, {:unknown_tool, name}}
    end
  end

  defp decode_arguments(action, arguments) do
    case Zoi.parse(action.schema(), arguments, coerce: true) do
      {:ok, params} -> action.validate_params(params)
      {:error, _reason} -> {:error, {:invalid_tool_arguments, tool_name(action)}}
    end
  end

  defp tool_name(action) do
    Enum.find_value(@tools, fn {name, tool} ->
      if tool.action == action, do: name
    end)
  end
end
