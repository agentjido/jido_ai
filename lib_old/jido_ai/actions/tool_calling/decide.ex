defmodule Jido.AI.Actions.ToolCalling.Decide do
  @moduledoc false
  use Jido.Action, name: "tool_calling_decide"
  alias Jido.AI.Model.Response

  def run(%{failure: failure}, _) when not is_nil(failure), do: {:error, failure}

  def run(state, _) do
    result = Response.to_result_map(state.turn)

    cond do
      not state.auto_execute or not Response.needs_tools?(state.turn) ->
        result =
          if state.round == 0,
            do: result,
            else:
              Map.merge(result, %{
                turns: state.round,
                messages: serialize(state.messages),
                usage: state.usage
              })

        {:ok, result}

      state.round >= state.max_turns ->
        {:ok,
         Map.merge(result, %{
           reason: :max_turns_reached,
           turns: state.max_turns,
           usage: state.usage
         })}

      true ->
        {:continue, state, Jido.AI.Actions.ToolCalling.ToolsFlow}
    end
  end

  defp serialize(messages) do
    Enum.map(messages, fn message ->
      %{role: message.role, content: Response.extract_from_content(message.content)}
      |> optional(:name, message.name)
      |> optional(:tool_call_id, message.tool_call_id)
      |> optional(:tool_calls, message.tool_calls)
    end)
  end

  defp optional(map, _, value) when value in [nil, []], do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
end
