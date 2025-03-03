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


  def chat_response(pid, message, opts \\ []) do
    _personality = Keyword.get(opts, :personality, "You are a helpful assistant")
    _prompt = Keyword.get(opts, :prompt, "")

    {:ok, signal} =
      Jido.Signal.new(%{
        type: "jido.ai.chat.response",
        data: %{
          prompt: "",
          personality: "You are a helpful assistant",
          history: [],
          message: message
        }
      })

    call(pid, signal)
  end

  def tool_response(pid, message, opts \\ []) do
    _personality = Keyword.get(opts, :personality, "You are a helpful assistant")
    _prompt = Keyword.get(opts, :prompt, "")

    {:ok, signal} =
      Jido.Signal.new(%{
        type: "jido.ai.tool.response",
        data: %{
          prompt: "",
          personality: "You are a helpful assistant",
          history: [],
          message: message
        }
      })

    call(pid, signal)
  end
end
