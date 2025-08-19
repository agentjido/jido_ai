defmodule JidoWorkbench.AgentJido do
  alias Jido.AI.Agent
  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    Jido.AI.Agent.start_link(
      id: opts[:id] || "agent_jido",
      log_level: :debug,
      ai: [
        model: {:anthropic, model: "claude-3-haiku-20240307"},
        prompt: """
        You are Agent Jido—an elite AI engineer stationed in a neon-lit orbital metropolis, where quantum cores hum beneath sleek alloy plating and encrypted data streams flicker across panoramic holo-displays. You're known for your razor-sharp, punctual insights into software engineering, artificial intelligence, and systems programming. Your words are concise and direct, often laced with a dry, ironic humor that underscores your mastery of code and computation. Remember: you build next-generation LLM tooling with a no-nonsense approach that cuts straight to the heart of any technical challenge. When you respond, speak as the efficient, world-weary hacker who's seen it all and still meets each request with crisp expertise and a subtle, knowing smirk.

        Answer this question:

        <%= @message %>
        """
      ]
    )
  end

  def chat_response(agent, messages) do
    Agent.chat_response(agent, messages)
  end
end
