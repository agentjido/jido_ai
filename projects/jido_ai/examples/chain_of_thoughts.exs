defmodule MyJido do
  use Jido, otp_app: :jido_ai
end

defmodule MyJido.ChainOfThought do
  defmodule Agent do
    use Jido.Agent,
      name: "chain_of_thought_agent",
      description: "A chain of thought agent",
      schema: [
        problem: [type: :string, required: true],
      ]
  end
  defmodule AnalyzeProblemAction do
    use Jido.Action,
      name: "analyze_problem",
      description: "Analyzes a problem and determines the next step",
      schema: [
        problem: [type: :string, required: true],
        session_id: [type: :string, required: true],
      ]

    def run(params, _context) do
      {:ok, params}
    end
  end

  def demo do
    IO.puts("Running Chain of Thoughts Demo")
  end
end
# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "chain_of_thoughts.exs" do
  MyJido.ChainOfThought.demo()
end
