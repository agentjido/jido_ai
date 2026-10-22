defmodule JidoAI.Examples.FailurePosition do
  @moduledoc "Read the saved reasoning position from a public standalone token."

  def saved_position(token, config) do
    with {:ok, state, _metadata} <- Jido.AI.Reasoning.ReAct.Token.decode_state(token, config),
         do: {:ok, state.iteration}
  end
end
