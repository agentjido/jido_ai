defmodule JidoAI.Examples.StateMigration do
  @moduledoc "Convert saved v2 AI data, then use the common native Agent and Flow."
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.State

  def resume(saved, config, evidence, opts) do
    with {:ok, state} <- State.migrate(saved, config, evidence),
         do: {:ok, state |> ReAct.stream_from_state(config, opts) |> ReAct.collect_stream()}
  end
end
