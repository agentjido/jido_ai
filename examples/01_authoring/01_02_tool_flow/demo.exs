alias JidoAI.Examples.ToolFlow.MultiRoundAgent, as: Agent

Logger.configure(level: :warning)
vars = Dotenvy.source!([".env", System.get_env()], side_effect: false)
key = Map.get(vars, "ANTHROPIC_API_KEY")
if not is_binary(key) or key == "", do: raise("Set ANTHROPIC_API_KEY in the environment or .env")
System.put_env("ANTHROPIC_API_KEY", key)
Application.put_env(:jido_ai, :model_aliases, Map.put(Jido.AI.Models.aliases(), :fast, "anthropic:claude-haiku-4-5"))

{:ok, supervisor} = Jido.start_link(name: JidoAI.ToolFlowDemo)

try do
  {:ok, server} = Jido.start_agent(JidoAI.ToolFlowDemo, Agent.new!(), turn_timeout: 65_000)

  try do
    started = System.monotonic_time(:millisecond)

    case Agent.calculate(server, Agent.prompt(),
           context: %{ai: %{assistant: %{options: [req_http_options: [retry: false]]}}},
           timeout: 65_000
         ) do
      {:ok, agent} ->
        {:ok, profile} = Jido.AI.Configuration.profile(agent)
        {:ok, history} = Jido.AI.History.read(agent.state, profile)
        tools = Enum.filter(history, &(&1.role == :tool))

        Enum.each(tools, fn tool ->
          text = Enum.map_join(tool.content, "", &Map.get(&1, :text, ""))
          IO.puts("Tool #{tool.name} (#{tool.tool_call_id}): #{text}")
        end)

        IO.puts("Answer: #{agent.state.answer}")

        IO.inspect(
          %{
            tool_results: length(tools),
            elapsed_ms: System.monotonic_time(:millisecond) - started,
            committed: Jido.AgentServer.agent(server).state == agent.state
          },
          label: "Run"
        )

        if length(tools) != 3, do: raise("Expected three tool results; inspect the run")

      {:error, error} ->
        IO.inspect(Map.take(error, [:message]), label: "Execution failure")

        raise(
          "Live request failed. Check credentials, provider availability, and execution limits. No answer was committed."
        )
    end
  after
    if Process.alive?(server), do: GenServer.stop(server)
  end
after
  Supervisor.stop(supervisor)
end
