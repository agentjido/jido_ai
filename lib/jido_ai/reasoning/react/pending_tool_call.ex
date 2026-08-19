defmodule Jido.AI.Reasoning.ReAct.PendingToolCall do
  @moduledoc """
  Tracks a tool call in the ReAct runtime.
  """

  alias Jido.AI.Effects.Applier

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "LLM tool call ID"),
              name: Zoi.string(description: "Tool/action name"),
              action_module: Zoi.atom(description: "Resolved action module") |> Zoi.optional(),
              arguments: Zoi.map(description: "Tool call arguments") |> Zoi.default(%{}),
              status: Zoi.atom(description: "Execution status") |> Zoi.default(:pending),
              result: Zoi.any(description: "Raw tool execution result") |> Zoi.optional(),
              attempts: Zoi.integer(description: "Execution attempts") |> Zoi.default(0),
              duration_ms: Zoi.integer(description: "Execution duration in milliseconds") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Returns the Zoi schema used to validate pending tool call entries.
  """
  @spec schema() :: term()
  def schema, do: @schema

  @doc """
  Builds a normalized pending tool call from an LLM tool call map.
  """
  @spec from_tool_call(map()) :: t()
  def from_tool_call(%{} = tool_call) do
    attrs =
      %{
        id: to_string(Map.get(tool_call, :id, Map.get(tool_call, "id", ""))),
        name: to_string(Map.get(tool_call, :name, Map.get(tool_call, "name", ""))),
        arguments: Map.get(tool_call, :arguments, Map.get(tool_call, "arguments", %{})) || %{}
      }
      |> maybe_put_action_module(Map.get(tool_call, :action_module, Map.get(tool_call, "action_module")))

    case Zoi.parse(@schema, attrs) do
      {:ok, call} -> call
      {:error, _} -> %__MODULE__{id: "", name: "", arguments: %{}}
    end
  end

  defp maybe_put_action_module(attrs, module) when is_atom(module) and not is_nil(module),
    do: Map.put(attrs, :action_module, module)

  defp maybe_put_action_module(attrs, _module), do: attrs

  @doc """
  Marks a pending call as completed with result, attempts, and duration metadata.
  """
  @spec complete(t(), Applier.result_tuple(), non_neg_integer(), non_neg_integer()) :: t()
  def complete(%__MODULE__{} = call, result, attempts, duration_ms) do
    %__MODULE__{
      call
      | result: result,
        status: result_status(result),
        attempts: max(attempts, 1),
        duration_ms: duration_ms
    }
  end

  defp result_status({:ok, _payload, _effects}), do: :ok
  defp result_status({:error, _reason, _effects}), do: :error
end
