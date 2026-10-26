defmodule Jido.AI.Actions.PlanPromptCache do
  @moduledoc "Builds the prompt-cache plan for one model request."

  alias Jido.AI.{Conversation, PromptCache, Runtime}

  use Jido.Action,
    name: "jido_ai_plan_prompt_cache",
    description: "Plan provider prompt-cache use",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, messages: messages, projection: projection}, context) do
    model = Enum.at(turn.models, turn.model_index)

    plan =
      PromptCache.plan(
        Conversation.decode!(turn.session),
        messages,
        model,
        turn.options,
        turn.prompt_cache_config,
        Runtime.now_ms(context)
      )
      |> Map.put(:projection, projection)

    {:ok, %{turn: turn, messages: messages, prompt_cache: plan}}
  end
end
