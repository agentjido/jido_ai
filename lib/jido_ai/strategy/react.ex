defmodule Jido.AI.Strategy.ReAct do
  @moduledoc "The default graph-first reasoning Flow."

  @default_instructions "Answer concisely. Use the available tools when they help. You can request multiple tools in one response."

  use Jido.Flow,
    id: "jido.ai/strategy/react",
    vsn: 1,
    name: "jido_ai_react",
    description: "A persisted conversation, model, and parallel tool graph",
    schema:
      Zoi.object(%{
        input: Zoi.string(),
        instructions: Zoi.string() |> Zoi.default(@default_instructions),
        model: Zoi.string() |> Zoi.default("openai:gpt-4o-mini"),
        fallback_models: Zoi.list(Zoi.string()) |> Zoi.default([]),
        options:
          Zoi.map()
          |> Zoi.default(%{max_tokens: 128, receive_timeout: 30_000, temperature: 0.0}),
        prompt_cache: Zoi.map() |> Zoi.default(%{enabled: false}),
        stream: Zoi.boolean() |> Zoi.default(false),
        review_tools: Zoi.boolean() |> Zoi.default(false),
        context_window:
          Zoi.object(%{
            max_messages: Zoi.integer(gte: 1, lte: 512) |> Zoi.default(64),
            max_bytes: Zoi.integer(gte: 1_024, lte: 2_000_000) |> Zoi.default(200_000)
          })
          |> Zoi.default(%{max_messages: 64, max_bytes: 200_000}),
        max_tool_rounds: Zoi.integer(gte: 0, lte: 8) |> Zoi.default(4),
        max_tool_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
        max_model_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
        max_retries: Zoi.integer(gte: 0, lte: 4) |> Zoi.default(1)
      }),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "start_request",
      action: Jido.AI.Actions.StartRequest,
      params: %{
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        fallback_models: input(:fallback_models),
        options: input(:options),
        prompt_cache: input(:prompt_cache),
        stream: input(:stream),
        review_tools: input(:review_tools),
        context_window: input(:context_window),
        max_tool_rounds: input(:max_tool_rounds),
        max_tool_calls: input(:max_tool_calls),
        max_model_calls: input(:max_model_calls),
        max_retries: input(:max_retries)
      }

    invoke "input_guard",
      decision: Jido.AI.Actions.CheckInput,
      expander: Jido.AI.Actions.ExpandNext,
      params: %{turn: result("start_request")}

    output result("input_guard")
  end
end
