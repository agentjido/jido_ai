defmodule JidoAI.Examples.Controls.Input do
  @moduledoc false
  use Jido.Action, name: "v3_example_input_control", schema: JidoAI.Examples.Schema.prompt()

  def run(input, context) do
    send(context.observer, :input_control)

    if context.authorized,
      do: {:ok, input},
      else: {:error, Jido.Action.Error.validation_error("case access denied")}
  end
end

defmodule JidoAI.Examples.Controls.Output do
  @moduledoc false
  use Jido.Action, name: "v3_example_output_control", schema: JidoAI.Examples.Schema.answer()

  def run(input, context) do
    send(context.observer, :output_control)

    if String.contains?(input.answer, "[evidence]"),
      do: {:ok, input},
      else: {:error, Jido.Action.Error.validation_error("answer has no evidence")}
  end
end

defmodule JidoAI.Examples.Controls.Flow do
  @moduledoc "Explicit application controls around model work and final state assembly."
  use Jido.Flow, name: "v3_example_controls", schema: JidoAI.Examples.Schema.prompt()

  flow do
    step "input", action: JidoAI.Examples.Controls.Input, params: input()
    step "model", action: JidoAI.Examples.Generate, params: result("input")
    step "output", action: JidoAI.Examples.Controls.Output, params: result("model")
    step "candidate", action: JidoAI.Examples.Commit, params: result("output")
    output result("candidate")
  end
end

defmodule JidoAI.Examples.Controls.Agent do
  @moduledoc "01_04: Rejected input, rejected output, and provider errors preserve live state."
  use Jido.Agent, name: "v3_example_controls_agent"

  agent do
    schema JidoAI.Examples.Schema.state()
  end

  routes do
    route "ai.ask", JidoAI.Examples.Controls.Flow
  end
end
