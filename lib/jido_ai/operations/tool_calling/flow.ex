defmodule Jido.AI.Actions.ToolCalling.RequestModel do
  @moduledoc false
  use Jido.Action, name: "tool_calling_request_model"
  alias Jido.AI.{Models, Turn, Usage}

  def run(state, context) do
    case Models.request(:text, state.model, state.messages, state.options, nil, context) do
      {:ok, response} ->
        turn = Turn.from_response(response, model: state.model)
        usage = state.usage |> Usage.merge(turn.usage) |> Usage.ensure_total_tokens()

        {:ok,
         %{
           state
           | turn: turn,
             usage: usage,
             messages: state.messages ++ [Turn.assistant_message(turn)]
         }}

      {:error, error} ->
        {:ok, %{state | failure: error}}
    end
  end
end

defmodule Jido.AI.Actions.ToolCalling.Decide do
  @moduledoc false
  use Jido.Action, name: "tool_calling_decide"
  alias Jido.AI.Turn

  def run(%{failure: failure, round: 0}, _) when not is_nil(failure), do: {:error, failure}

  def run(%{failure: failure} = state, _) when not is_nil(failure),
    do:
      {:ok,
       %{
         type: :error,
         reason: failure,
         turns: state.round,
         model: state.model,
         usage: state.usage
       }}

  def run(state, _) do
    result = Turn.to_result_map(state.turn)

    cond do
      not state.auto_execute or not Turn.needs_tools?(state.turn) ->
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
      %{role: message.role, content: Turn.extract_from_content(message.content)}
      |> optional(:name, message.name)
      |> optional(:tool_call_id, message.tool_call_id)
      |> optional(:tool_calls, message.tool_calls)
    end)
  end

  defp optional(map, _, value) when value in [nil, []], do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
end

defmodule Jido.AI.Actions.ToolCalling.RunTools do
  @moduledoc false
  use Jido.Action, name: "tool_calling_run_tools"

  def run(state, context) do
    with {:ok, turn} <-
           Jido.AI.Turn.run_tools(state.turn, context, tools: state.tools, timeout: state.timeout) do
      {:ok,
       %{
         state
         | round: state.round + 1,
           messages: state.messages ++ Jido.AI.Turn.tool_messages(turn)
       }}
    end
  end
end

defmodule Jido.AI.Actions.ToolCalling.ModelFlow do
  @moduledoc false
  use Jido.Flow, name: "tool_calling_model"

  flow do
    dispatch("model",
      decision: Jido.AI.Actions.ToolCalling.RequestModel,
      expander: Jido.AI.Actions.ToolCalling.Decide,
      params: input()
    )

    output(result("model"))
  end
end

defmodule Jido.AI.Actions.ToolCalling.ToolsFlow do
  @moduledoc false
  use Jido.Flow, name: "tool_calling_tools"

  flow do
    step("tools", action: Jido.AI.Actions.ToolCalling.RunTools, params: input())

    dispatch("model",
      decision: Jido.AI.Actions.ToolCalling.RequestModel,
      expander: Jido.AI.Actions.ToolCalling.Decide,
      params: result("tools")
    )

    output(result("model"))
  end
end
