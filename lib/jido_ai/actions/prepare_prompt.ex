defmodule Jido.AI.Actions.PreparePrompt do
  @moduledoc """
  Builds portable model messages for an initial or continued round.
  """

  use Jido.Action,
    name: "jido_ai_prepare_prompt",
    description: "Build the messages for one Agent round",
    schema:
      Zoi.object(%{
        input: Zoi.string(),
        instructions: Zoi.string(),
        mode: Zoi.enum([:initial, :continue]),
        history: Zoi.list(Zoi.map())
      }),
    output_schema: Zoi.object(%{messages: Zoi.list(Zoi.map())})

  @impl Jido.Action
  def run(%{mode: :initial} = params, _context) do
    {:ok,
     %{
       messages: [
         %{role: :system, content: params.instructions},
         %{role: :user, content: params.input}
       ]
     }}
  end

  def run(%{mode: :continue} = params, _context) do
    {:ok,
     %{
       messages:
         [
           %{role: :system, content: params.instructions},
           %{role: :user, content: params.input}
         ] ++ params.history
     }}
  end
end
