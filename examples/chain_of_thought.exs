defmodule MyJido do
  use Jido, otp_app: :jido_ai
end

defmodule MyJido.ChainOfThought do
  defmodule Agent do
    use Jido.Agent, name: "thinking_agent"

    require Logger

    @default_opts [
      agent: __MODULE__,
      mode: :auto,
      log_level: :debug,
      skills: [
        # Jido.Skills.Arithmetic,
        # Jido.Skills.StateManager,
        # Jido.Skills.BasicActions,
        Jido.AI.Skill
      ]
    ]

    @impl true
    def start_link(opts) when is_list(opts) do
      name = Keyword.fetch!(opts, :name)

      server_opts =
        @default_opts
        |> Keyword.merge(opts)
        |> Keyword.put(:id, name)

      Jido.AI.Agent.start_link(server_opts)
    end

    defdelegate generate_text(pid, message), to: Jido.AI.Agent
    defdelegate generate_object(pid, message, opts), to: Jido.AI.Agent
    defdelegate stream_text(pid, message), to: Jido.AI.Agent
    defdelegate stream_object(pid, message, opts), to: Jido.AI.Agent
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
    {:ok, pid} = Agent.start_link(name: "thinking_agent")
    IO.puts("Agent started")
    IO.puts("Sending signal to agent")
    {:ok, response} = Agent.generate_text(pid, "What is the capital of France?")
    IO.puts("Response: #{response}")
  end
end
# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "chain_of_thought.exs" do
  MyJido.ChainOfThought.demo()
end
