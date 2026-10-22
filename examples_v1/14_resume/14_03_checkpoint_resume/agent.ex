defmodule JidoAI.Examples.CheckpointResume do
  @moduledoc "Stop at a public checkpoint and resume through a fresh v3 Agent."

  def through_checkpoint(events, reason, occurrence \\ 1) do
    {collected, _} =
      Enum.reduce_while(events, {[], 0}, fn event, {acc, count} ->
        match? = event.kind == :checkpoint and event.data.reason == reason
        count = count + if(match?, do: 1, else: 0)
        next = {[event | acc], count}
        if match? and count == occurrence, do: {:halt, next}, else: {:cont, next}
      end)

    Enum.reverse(collected)
  end
end

defmodule JidoAI.Examples.CheckpointResume.Reloadable do
  use Jido.Action,
    name: "reloadable",
    description: "A tool with a checked code identity",
    schema: Zoi.object(%{})

  def run(_, _), do: {:ok, %{version: 1}}
end
