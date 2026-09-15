defmodule Jido.AI.Actions.ToolCalling.RequestModel do
  @moduledoc false
  use Jido.Action, name: "tool_calling_request_model"
  alias Jido.AI.{Turn, Usage}

  def run(state, context) do
    case Jido.AI.Model.Transport.request(
           :text,
           state.model,
           state.messages,
           state.options,
           nil,
           context
         ) do
      {:ok, response} ->
        turn = Turn.from_response(response, model: state.model)

        turn_usage =
          case Usage.normalize(turn.usage) do
            %{} = usage -> Usage.ensure_total_tokens(usage)
            nil -> %{}
          end

        usage = Usage.merge(state.usage, turn_usage)

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
