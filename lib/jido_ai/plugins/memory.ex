defmodule Jido.AI.Skills.MemorySkill do
  @moduledoc """
  Plugin that provides memory tools to an agent.

  Exposes Store, Recall, and Forget actions as tools that can be used
  by ReAct agents to remember and retrieve information across conversations.

  ## Usage with ReActAgent

      use Jido.AI.ReActAgent,
        name: "my_agent",
        tools: [
          Jido.AI.Actions.Memory.Store,
          Jido.AI.Actions.Memory.Recall,
          Jido.AI.Actions.Memory.Forget
        ],
        plugins: [Jido.AI.Skills.MemorySkill]

  Or use `tools_from_skills/1` to auto-extract:

      @skills [Jido.AI.Skills.MemorySkill]

      use Jido.AI.ReActAgent,
        name: "my_agent",
        tools: Jido.AI.ReActAgent.tools_from_skills(@skills),
        plugins: @skills
  """

  use Jido.Plugin,
    name: "ai_memory",
    description: "Per-agent memory with pluggable backend (ETS default)",
    category: "ai",
    tags: ["memory", "state", "recall"],
    state_key: :__memory_skill__,
    actions: [
      Jido.AI.Actions.Memory.Store,
      Jido.AI.Actions.Memory.Recall,
      Jido.AI.Actions.Memory.Forget
    ]

  @impl Jido.Plugin
  def mount(_agent, _config) do
    {:ok, %{}}
  end
end
