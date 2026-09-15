defmodule JidoAI.Examples.StandaloneActions.Flow do
  use Jido.Flow, name: "standalone_action_example"

  flow do
    step "start", action: Jido.AI.Reasoning.ReAct.Actions.Start, params: input()

    step "collect",
      action: Jido.AI.Reasoning.ReAct.Actions.Collect,
      params: %{events: result("start", :events)}

    output result("collect")
  end
end
