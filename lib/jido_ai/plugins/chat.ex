# Ensure actions are compiled before the plugin
require Jido.AI.Actions.LLM.Chat
require Jido.AI.Actions.LLM.Complete
require Jido.AI.Actions.LLM.Embed
require Jido.AI.Actions.LLM.GenerateObject
require Jido.AI.Actions.ToolCalling.CallWithTools
require Jido.AI.Actions.ToolCalling.ExecuteTool
require Jido.AI.Actions.ToolCalling.ListTools

defmodule Jido.AI.Plugins.Chat do
  @moduledoc """
  Conversational capability plugin with built-in tool calling support.

  `chat.message` routes to tool-aware execution and defaults to tool
  auto-execution unless explicitly disabled.
  """

  use Jido.Plugin,
    name: "chat",
    state_key: :chat,
    actions: [
      Jido.AI.Actions.ToolCalling.CallWithTools,
      Jido.AI.Actions.ToolCalling.ExecuteTool,
      Jido.AI.Actions.ToolCalling.ListTools,
      Jido.AI.Actions.LLM.Chat,
      Jido.AI.Actions.LLM.Complete,
      Jido.AI.Actions.LLM.Embed,
      Jido.AI.Actions.LLM.GenerateObject
    ],
    description: "Provides conversational AI with built-in tool calling",
    category: "ai",
    tags: ["chat", "conversation", "tool-calling", "llm"],
    vsn: "2.0.0"

  alias Jido.AI.ToolAdapter

  @impl Jido.Plugin
  def mount(_agent, config) do
    tools = Map.get(config, :tools, [])
    tools_map = ToolAdapter.to_action_map(tools)

    initial_state = %{
      default_model: Map.get(config, :default_model, :capable),
      default_max_tokens: Map.get(config, :default_max_tokens, 4096),
      default_temperature: Map.get(config, :default_temperature, 0.7),
      default_system_prompt: Map.get(config, :default_system_prompt),
      auto_execute: Map.get(config, :auto_execute, true),
      max_turns: Map.get(config, :max_turns, 10),
      tool_policy: Map.get(config, :tool_policy, :allow_all),
      tools: tools_map,
      available_tools: Map.keys(tools_map)
    }

    {:ok, initial_state}
  end

  def schema do
    Zoi.object(%{
      default_model: Zoi.any(description: "Default model alias or model spec") |> Zoi.default(:capable),
      default_max_tokens: Zoi.integer(description: "Default max tokens") |> Zoi.default(4096),
      default_temperature: Zoi.float(description: "Default sampling temperature") |> Zoi.default(0.7),
      default_system_prompt: Zoi.string(description: "Default system prompt") |> Zoi.optional(),
      auto_execute:
        Zoi.boolean(description: "Automatically execute tool calls by default")
        |> Zoi.default(true),
      max_turns: Zoi.integer(description: "Maximum conversation turns for auto tool execution") |> Zoi.default(10),
      tool_policy: Zoi.atom(description: "Tool policy mode") |> Zoi.default(:allow_all),
      available_tools:
        Zoi.list(Zoi.string(description: "Registered tool name"), description: "Available tool names")
        |> Zoi.default([])
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"chat.message", Jido.AI.Actions.ToolCalling.CallWithTools},
      {"chat.simple", Jido.AI.Actions.LLM.Chat},
      {"chat.complete", Jido.AI.Actions.LLM.Complete},
      {"chat.embed", Jido.AI.Actions.LLM.Embed},
      {"chat.generate_object", Jido.AI.Actions.LLM.GenerateObject},
      {"chat.execute_tool", Jido.AI.Actions.ToolCalling.ExecuteTool},
      {"chat.list_tools", Jido.AI.Actions.ToolCalling.ListTools}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(_signal, _context), do: {:ok, :continue}

  @impl Jido.Plugin
  def transform_result(_action, result, _context), do: result

  def signal_patterns do
    [
      "chat.message",
      "chat.simple",
      "chat.complete",
      "chat.embed",
      "chat.generate_object",
      "chat.execute_tool",
      "chat.list_tools"
    ]
  end
end
