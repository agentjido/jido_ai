defmodule Jido.AI.Reasoning.ReAct.Actions.Cancel do
  @moduledoc """
  Cancel an inactive ReAct checkpoint by issuing a new cancelled token.
  """

  use Jido.Action,
    name: "react_cancel",
    description: "Cancel a ReAct checkpoint token",
    category: "ai",
    tags: ["react", "runtime", "cancel"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        checkpoint_token: Zoi.string(),
        reason: Zoi.atom() |> Zoi.default(:cancelled),
        model: Zoi.any() |> Zoi.optional(),
        system_prompt: Zoi.string() |> Zoi.optional(),
        tools: Zoi.any() |> Zoi.optional(),
        max_iterations: Zoi.integer() |> Zoi.default(10),
        token_secret: Zoi.string() |> Zoi.optional(),
        token_ttl_ms: Zoi.integer() |> Zoi.optional(),
        token_compress?: Zoi.boolean() |> Zoi.default(false)
      })

  alias Jido.AI.Reasoning.ReAct.Actions.Helpers
  alias Jido.AI.Reasoning.ReAct

  @impl Jido.Action
  def run(params, context) do
    config = Helpers.build_config(params, context)

    with {:ok, token} <- ReAct.cancel(params[:checkpoint_token], config, params[:reason]) do
      {:ok, %{cancelled: true, token: token}}
    end
  end
end
