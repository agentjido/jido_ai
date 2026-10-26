defmodule Jido.AI.Reasoning.ReAct do
  @moduledoc """
  The canonical graph-first ReAct reasoning recipe.

  The root Flow starts the request, applies the default input guard, invokes
  the ReAct loop, and finalizes the terminal outcome. Model rounds, tool
  review, and all recipe Actions are public modules under this namespace.
  """

  alias Jido.AI.Reasoning.ReAct.Actions.{
    DecideInput,
    ExpandNext,
    FinalizeTurn,
    GuardInput,
    StartRequest
  }

  @default_instructions "Answer concisely. Use the available tools when they help. You can request multiple tools in one response."

  use Jido.Flow,
    id: "jido.ai/reasoning/react",
    vsn: 1,
    name: "jido_ai_reasoning_react",
    description: "A persisted conversation, model, and parallel tool graph",
    schema:
      Zoi.object(
        %{
          input: Zoi.string(),
          instructions: Zoi.string() |> Zoi.default(@default_instructions),
          model: Zoi.string() |> Zoi.default("openai:gpt-4o-mini"),
          fallback_models: Zoi.list(Zoi.string()) |> Zoi.default([]),
          options:
            Zoi.map()
            |> Zoi.default(%{max_tokens: 128, receive_timeout: 30_000, temperature: 0.0}),
          prompt_cache:
            Zoi.object(
              %{
                enabled: Zoi.boolean() |> Zoi.default(false),
                ttl:
                  Zoi.union([Zoi.string(), Zoi.integer(gte: 0)])
                  |> Zoi.optional()
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{enabled: false}),
          stream: Zoi.boolean() |> Zoi.default(false),
          review_tools: Zoi.boolean() |> Zoi.default(false),
          context:
            Zoi.object(
              %{
                max_messages: Zoi.integer(gte: 1, lte: 512) |> Zoi.default(64),
                max_bytes: Zoi.integer(gte: 1_024, lte: 2_000_000) |> Zoi.default(200_000)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{max_messages: 64, max_bytes: 200_000}),
          limits:
            Zoi.object(
              %{
                model_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
                tool_rounds: Zoi.integer(gte: 0, lte: 8) |> Zoi.default(4),
                tool_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
                retries: Zoi.integer(gte: 0, lte: 4) |> Zoi.default(1)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{model_calls: 8, tool_rounds: 4, tool_calls: 8, retries: 1})
        },
        unrecognized_keys: :error
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "start_request",
      action: StartRequest,
      params: %{
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        fallback_models: input(:fallback_models),
        options: input(:options),
        prompt_cache: input(:prompt_cache),
        stream: input(:stream),
        review_tools: input(:review_tools),
        context_window: input(:context),
        max_tool_rounds: input([:limits, :tool_rounds]),
        max_tool_calls: input([:limits, :tool_calls]),
        max_model_calls: input([:limits, :model_calls]),
        max_retries: input([:limits, :retries])
      }

    step "input_guard",
      action: GuardInput,
      params: %{turn: result("start_request")}

    invoke "loop",
      decision: DecideInput,
      expander: ExpandNext,
      params: %{
        turn: result("start_request"),
        guard: result("input_guard")
      }

    step "finalize",
      action: FinalizeTurn,
      params: %{outcome: result("loop")}

    output result("finalize")
  end
end
