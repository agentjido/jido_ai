defmodule Jido.AI.Execution.Flow do
  @moduledoc false

  def build(profile) do
    alias Jido.Flow.Builder, as: B

    B.new(name: "ai_#{profile.id}", schema: Zoi.object(%{query: Jido.AI.Query.schema()}))
    |> B.step("prepare", Jido.AI.Execution.Prepare, %{
      profile_id: profile.id,
      query: B.input(:query)
    })
    |> B.dispatch(
      "reason",
      Jido.AI.Execution.CallModel,
      Jido.AI.Execution.Decide,
      B.result("prepare")
    )
    |> B.output(B.result("reason"))
    |> B.build()
  end
end
