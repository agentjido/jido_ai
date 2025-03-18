defmodule Jido.AI.Agent do
  @moduledoc """
  General purpose AI agent powered by Jido
  """
  use Jido.Agent,
    name: "jido_ai_agent",
    description: "General purpose AI agent powered by Jido",
    category: "AI Agents",
    tags: ["AI", "Agent"],
    vsn: "0.1.0"

  @default_opts [
    skills: [Jido.AI.Skill],
    agent: __MODULE__
  ]

  @impl true
  def start_link(opts) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end

  def chat_response(pid, message) when is_binary(message) do
    {:ok, signal} = build_signal("jido.ai.chat.response", message)

    call(pid, signal)
  end

  def tool_response(pid, message) do
    {:ok, signal} = build_signal("jido.ai.tool.response", message)

    call(pid, signal)
  end

  def boolean_response(pid, message) do
    {:ok, signal} = build_signal("jido.ai.boolean.response", message)

    call(pid, signal)
  end

  defp build_signal(type, message) do
    Jido.Signal.new(%{
      type: type,
      data: %{message: message}
    })
  end
end
