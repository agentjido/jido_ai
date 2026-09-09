defmodule JidoAI.Examples.StructuredOutput.Attempt do
  @moduledoc "One structured attempt. Only schema validation failures enter repair."
  use Jido.Action, name: "v3_example_object_attempt"

  def run(%{state: state}, context) do
    prompt = state.query <> "\nValidation feedback: " <> state.feedback
    # Request the application schema and keep repair inside the bounded Flow.
    with {:ok, response} <-
           ReqLLM.generate_object(
             context.model,
             prompt,
             JidoAI.Examples.Schema.answer(),
             context.model_options
           ) do
      case Zoi.parse(JidoAI.Examples.Schema.answer(), ReqLLM.Response.object(response)) do
        {:ok, object} ->
          {:ok, %{state | answer: object.answer, missing: 0, attempts: state.attempts + 1}}

        {:error, issues} ->
          {:ok, %{state | feedback: inspect(issues), attempts: state.attempts + 1}}
      end
    end
  end
end

defmodule JidoAI.Examples.StructuredOutput.Flow do
  @moduledoc "Two total attempts. Failed repair cannot reach the state assembler."
  use Jido.Flow, name: "v3_example_object_flow", schema: JidoAI.Examples.Schema.prompt()

  flow do
    iterate "repair" do
      state Zoi.object(%{
              query: Zoi.string(),
              answer: Zoi.string(),
              feedback: Zoi.string(),
              missing: Zoi.integer(),
              attempts: Zoi.integer()
            }),
            initial: %{query: input(:query), answer: "", feedback: "", missing: 1, attempts: 0}

      action JidoAI.Examples.StructuredOutput.Attempt
      params %{state: state()}
      update body_result()
      while state(:missing) > 0
      max_iterations 2
    end

    step "candidate",
      action: JidoAI.Examples.Commit,
      params: %{answer: result("repair", [:state, :answer])}

    output result("candidate")
  end
end

defmodule JidoAI.Examples.StructuredOutput.Agent do
  @moduledoc "01_03: Typed output and bounded repair preserve unrelated state."
  use Jido.Agent, name: "v3_example_object_agent"

  agent do
    schema JidoAI.Examples.Schema.state()
  end

  routes do
    route "ai.ask", JidoAI.Examples.StructuredOutput.Flow
  end
end
