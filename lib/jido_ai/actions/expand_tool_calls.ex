defmodule Jido.AI.Actions.ExpandToolCalls do
  @moduledoc """
  Completes a rejected tool request or expands validated calls as a Parallel Flow.
  """

  alias Jido.AI.ToolRegistry
  alias Jido.Flow.Ref

  use Jido.Action,
    name: "jido_ai_expand_tool_calls",
    description: "Expand validated model tool calls as a Parallel Flow",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, result: result}, _context), do: {:ok, result}

  def run(%{kind: :continue, input: %{tool_calls: tool_calls} = input}, _context) do
    with {:ok, calls} <- resolve_calls(tool_calls),
         {:ok, flow} <- build_flow(calls) do
      {:continue, input, flow}
    end
  end

  def run(%{kind: :continue}, _context), do: {:error, :invalid_tool_calls}

  defp resolve_calls(calls) when is_list(calls) and calls != [] do
    calls
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, resolved} ->
      case ToolRegistry.resolve_call(call) do
        {:ok, value} -> {:cont, {:ok, [value | resolved]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp resolve_calls(calls), do: {:error, {:invalid_tool_calls, calls}}

  defp build_flow(calls) do
    Jido.Flow.new(%{
      name: "jido_ai_tool_calls",
      description: "Execute validated model tool calls as parallel Action nodes",
      schema: Zoi.map(),
      output_schema: Zoi.map(),
      components: [parallel(calls), continuation(calls)],
      output: Ref.result("next")
    })
  end

  defp parallel(calls) do
    %{
      kind: :parallel,
      name: "tools",
      actions:
        calls
        |> Enum.with_index()
        |> Enum.map(fn {call, index} ->
          %{
            name: action_name(index),
            action: call.action,
            params: call.params
          }
        end)
    }
  end

  defp continuation(calls) do
    %{
      kind: :dispatch,
      name: "next",
      decision: Jido.AI.Actions.RecordToolResults,
      expander: Jido.AI.Actions.ExpandToolResults,
      params: %{
        allowed_tools: Ref.input(:allowed_tools),
        history: Ref.input(:history),
        input: Ref.input(:input),
        iteration: Ref.input(:iteration),
        max_iterations: Ref.input(:max_iterations),
        max_tool_calls: Ref.input(:max_tool_calls),
        results: result_refs(calls),
        tool_call_count: Ref.input(:tool_call_count)
      }
    }
  end

  defp result_refs(calls) do
    calls
    |> Enum.with_index()
    |> Enum.map(fn {call, index} ->
      %{
        id: call.id,
        name: call.name,
        output: Ref.result("tools", [index, :value])
      }
    end)
  end

  defp action_name(index), do: "tool_#{index}"
end
