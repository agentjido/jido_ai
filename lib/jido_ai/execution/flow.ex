defmodule Jido.AI.Execution.Flow do
  @moduledoc false

  def build(profile) do
    alias Jido.Flow.{Dispatch, Ref, Step}

    Jido.Flow.new(
      name: "ai_#{profile.id}",
      schema: Zoi.object(%{query: Jido.AI.Query.schema()}),
      components: [
        Step.new!(
          name: "prepare",
          action: Jido.AI.Execution.Prepare,
          params: %{profile_id: profile.id, query: Ref.input(:query)}
        ),
        Dispatch.new!(
          name: "reason",
          decision: Jido.AI.Execution.CallModel,
          expander: Jido.AI.Execution.Decide,
          params: Ref.result("prepare")
        )
      ],
      output: Ref.result("reason")
    )
  end
end
