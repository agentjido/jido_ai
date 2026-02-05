defmodule Jido.AI.Examples.MemoryAgent do
  @moduledoc """
  Demo agent with persistent memory across conversations.

  Uses the `Jido.AI.Memory` system to store, recall, and forget facts.
  Memory persists in ETS across multiple `ask_sync` calls on the same
  agent instance, demonstrating cross-conversation recall.

  ## Usage

      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.MemoryAgent)

      # Store something in conversation 1
      {:ok, _} = Jido.AI.Examples.MemoryAgent.ask_sync(pid, "Remember that my name is Alice")

      # Recall it in conversation 2
      {:ok, _} = Jido.AI.Examples.MemoryAgent.ask_sync(pid, "What is my name?")

  ## CLI Usage

      mix run scripts/test_memory_agent.exs
  """

  use Jido.AI.ReActAgent,
    name: "memory_agent",
    description: "Agent with persistent memory for facts and preferences",
    tools: [
      Jido.AI.Actions.Memory.Store,
      Jido.AI.Actions.Memory.Recall,
      Jido.AI.Actions.Memory.Forget
    ],
    plugins: [Jido.AI.Skills.MemorySkill],
    system_prompt: """
    You are a helpful assistant with persistent memory.

    You have three memory tools available:
    - memory_store: Save a fact or preference for later. Use descriptive keys (e.g., "user_name", "favorite_color") and tag entries for easy recall (e.g., tags: ["preference", "personal"]).
    - memory_recall: Look up stored memories by exact key or by tags.
    - memory_forget: Delete stored memories by key or tags.

    IMPORTANT RULES:
    1. When the user tells you something about themselves (name, preferences, facts), ALWAYS use memory_store to save it immediately.
    2. When the user asks about something you might have stored, ALWAYS use memory_recall first to check.
    3. Use clear, descriptive keys like "user_name", "favorite_color", "home_city".
    4. Tag entries meaningfully: ["personal"], ["preference"], ["fact"], etc.
    5. After storing, confirm what you remembered.
    6. After recalling, use the information naturally in your response.
    7. If recall returns found: false, say you don't have that information stored.
    """,
    max_iterations: 6
end
