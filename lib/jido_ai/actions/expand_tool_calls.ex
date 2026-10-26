defmodule Jido.AI.Actions.ExpandToolCalls do
  @moduledoc "Expands validated calls as a Parallel Flow or starts a review wait."

  alias Jido.AI.ToolRegistry
  alias Jido.Flow.Ref

  use Jido.Action,
    name: "jido_ai_expand_tool_calls",
    description: "Expand validated model tool calls",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context),
    do: {:continue, output, Jido.AI.Flows.Finalize}

  def run(%{kind: :review, input: input}, _context),
    do: {:continue, input, Jido.AI.Flows.ToolReview}

  def run(%{kind: :continue, input: %{turn: turn} = input}, _context) do
    with {:ok, calls} <- resolve_calls(turn.model_outcome.tool_calls),
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
      description: "Execute validated tool calls as parallel Actions",
      schema: Zoi.object(%{turn: Zoi.any()}),
      output_schema: Zoi.map(),
      components: [parallel(calls), continuation(calls)],
      output: Ref.result("next")
    })
  end

  defp parallel(calls) do
    %{
      kind: :parallel,
      name: "tools",
      on_error: :collect_errors,
      actions:
        calls
        |> Enum.with_index()
        |> Enum.map(fn {call, index} ->
          %{name: action_name(index), action: call.action, params: call.params}
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
        turn: Ref.input(:turn),
        results: result_refs(calls)
      }
    }
  end

  defp result_refs(calls) do
    calls
    |> Enum.with_index()
    |> Enum.map(fn {call, index} ->
      %{id: call.id, name: call.name, outcome: Ref.result("tools", [index])}
    end)
  end

  defp action_name(index), do: "tool_#{index}"
end
