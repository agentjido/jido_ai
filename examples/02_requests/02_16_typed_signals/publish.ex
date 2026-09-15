defmodule JidoAI.Examples.TypedSignals.Publish do
  use Jido.Action, name: "publish_ai_event"

  def run(%{event: event}, context) do
    with {:ok, directives} <- Jido.AI.Signal.emit(event),
         do:
           {:ok,
            %{
              context.agent_state
              | published: context.agent_state.published + length(directives)
            }, directives}
  end

  def run(%{typed: typed}, context),
    do:
      {:ok, %{context.agent_state | published: context.agent_state.published + 1},
       [%Jido.Agent.Directive.Emit{signal: typed}]}
end
