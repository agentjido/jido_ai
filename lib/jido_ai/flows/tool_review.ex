defmodule Jido.AI.Flows.ToolReview do
  @moduledoc "Waits for a durable tool approval, denial, or timeout."

  use Jido.Flow,
    name: "jido_ai_tool_review",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.map()

  flow do
    step "request",
      action: Jido.AI.Actions.RequestToolReview,
      params: %{turn: input(:turn)}

    selection "decision" do
      needs ["request"]

      await("approved",
        event: "jido.ai.review.approved",
        match: %{request_id: result("request", [:turn, :request_id])}
      )

      await("denied",
        event: "jido.ai.review.denied",
        match: %{request_id: result("request", [:turn, :request_id])}
      )

      timer("expired", after_ms: 300_000)
    end

    invoke "next",
      decision: Jido.AI.Actions.ResolveToolReview,
      expander: Jido.AI.Actions.ExpandNext,
      params: %{
        turn: result("request", :turn),
        decision: result("decision")
      }

    output result("next")
  end
end
