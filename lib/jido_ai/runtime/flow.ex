defmodule Jido.AI.Runtime.Flow do
  @moduledoc false

  def build(profile) do
    alias Jido.Flow.Builder, as: B

    B.new(name: "ai_#{profile.id}", schema: Zoi.object(%{query: Jido.AI.Query.schema()}))
    |> B.step("prepare", Jido.AI.Runtime.Prepare, %{
      profile_id: profile.id,
      query: B.input(:query)
    })
    |> B.dispatch(
      "reason",
      Jido.AI.Runtime.CallModel,
      Jido.AI.Runtime.Decide,
      B.result("prepare")
    )
    |> B.output(B.result("reason"))
    |> B.build()
  end
end
