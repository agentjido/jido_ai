defmodule JidoAI.Examples.Schema do
  @moduledoc false
  def prompt, do: Zoi.object(%{query: Zoi.string()})
  def answer, do: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}, coerce: true)

  def state do
    Zoi.object(%{
      answer: Zoi.string() |> Zoi.default(""),
      case_id: Zoi.string() |> Zoi.default("case-42"),
      commits: Zoi.integer() |> Zoi.default(0)
    })
  end
end

defmodule JidoAI.Examples.Generate do
  @moduledoc "Application projection of the shared AI model operation."
  use Jido.Action, name: "v3_example_generate", schema: JidoAI.Examples.Schema.prompt()

  def run(%{query: query}, context) do
    request = %{
      model: context.model,
      messages: query,
      options: context.model_options,
      schema: nil
    }

    with {:ok, %{response: response}} <- Jido.AI.Operations.Generate.run(request, context) do
      {:ok, %{answer: ReqLLM.Response.text(response)}}
    end
  end
end

defmodule JidoAI.Examples.Commit do
  @moduledoc "Assembles a complete domain candidate. It does not commit the live Agent."
  use Jido.Action, name: "v3_example_commit", schema: JidoAI.Examples.Schema.answer()

  def run(%{answer: answer}, context) do
    state = context.agent_state
    {:ok, %{state | answer: answer, commits: state.commits + 1}}
  end
end
