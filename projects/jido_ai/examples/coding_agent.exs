require Logger
defmodule CodingDemo do
  use Jido, otp_app: :jido_ai
require Logger

  defmodule Agent do
    use Jido.Agent, name: "coding_agent"

    def start_link(opts \\ []) do
      Jido.AI.Agent.start_link(
        agent: __MODULE__,
        ai: [
          default_model: "openai:gpt-4o-mini",
        ]
      )
    end

    def run_task(agent_ref, messages, opts \\ [], timeout \\ @default_timeout) do
      data =
        opts
        |> Keyword.put(:messages, messages)
        |> Map.new()

      with {:ok, signal} <- Jido.Signal.new("run_task", data),
           {:ok, result_signal} <- Jido.Agent.call(agent_ref, signal, timeout) do
        result_signal
      end
    end
  end

  def demo do
    task = "Create a simple Elixir script that reads a JSON file called 'data.json', counts the number of objects in it, and writes the count to a file called 'count.txt'"

    Logger.info("🚀 Starting coding agent demo...")

    # Start the agent with skills
    {:ok, _agent_pid} = Agent.start_link(
      routes: [
        {"run_task", CodingDemo.RunTaskAction},
        {"loop_task", CodingDemo.LoopTaskAction},
      ],
      skills: [
        Jido.Skills.Files,
        JidoAI.Skills.Exec
      ]
    )
  end
end
# Set up logging
Logger.configure(level: :debug)

# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "coding_agent.exs" do
  CodingDemo.demo()
end
