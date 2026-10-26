defmodule Jido.AI.Flows.ModelRound do
  @moduledoc """
  Runs one guarded model round and dispatches its explicit outcome.
  """

  use Jido.Flow,
    name: "jido_ai_model_round",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  flow do
    choice "prompt" do
      option "initial",
        condition: input(:history) == [],
        action: Jido.AI.Actions.PreparePrompt,
        params: %{
          history: input(:history),
          input: input(:input),
          instructions:
            "Answer concisely. Use the available tools for arithmetic. You can request multiple tools in one response.",
          mode: :initial
        }

      otherwise action: Jido.AI.Actions.PreparePrompt,
                params: %{
                  history: input(:history),
                  input: input(:input),
                  instructions:
                    "Answer concisely. Use the available tools for arithmetic. You can request multiple tools in one response.",
                  mode: :continue
                }
    end

    step "model",
      action: Jido.AI.Actions.CallModel,
      params: %{
        allowed_tools: input(:allowed_tools),
        history: input(:history),
        input: input(:input),
        iteration: input(:iteration),
        max_iterations: input(:max_iterations),
        max_tool_calls: input(:max_tool_calls),
        messages: result("prompt", :messages),
        model: "openai:gpt-4o-mini",
        options: %{
          max_tokens: 128,
          receive_timeout: 30_000,
          temperature: 0.0
        },
        tool_call_count: input(:tool_call_count)
      }

    step "output_guard",
      action: Jido.AI.Actions.CheckOutput,
      params: %{
        kind: result("model", :kind),
        text: result("model", :text)
      }

    dispatch "next",
      decision: Jido.AI.Actions.DecideModelNext,
      expander: Jido.AI.Actions.ExpandModelNext,
      params: %{
        allowed_tools: result("model", :allowed_tools),
        history: result("model", :history),
        input: result("model", :input),
        iteration: result("model", :iteration),
        kind: result("model", :kind),
        max_iterations: result("model", :max_iterations),
        max_tool_calls: result("model", :max_tool_calls),
        output_allowed: result("output_guard", :allowed),
        output_reason: result("output_guard", :reason),
        text: result("model", :text),
        tool_call_count: result("model", :tool_call_count),
        tool_calls: result("model", :tool_calls)
      }

    output result("next")
  end
end
