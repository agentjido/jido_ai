# Ensure actions are compiled before the plugin
require Jido.AI.Actions.ToolCalling.CallWithTools
require Jido.AI.Actions.ToolCalling.ExecuteTool
require Jido.AI.Actions.ToolCalling.ListTools

defmodule Jido.AI.Plugins.ToolCalling do
  @moduledoc """
  A Jido.Plugin providing LLM tool/function calling capabilities.

  This plugin enables LLMs to call registered tools as functions during generation,
  with support for automatic tool execution and multi-turn conversations.

  ## Actions

  * `CallWithTools` - Send prompt to LLM with available tools, handle tool calls
  * `ExecuteTool` - Directly execute a tool by name with parameters
  * `ListTools` - List all available tools with their schemas

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        plugins: [
          {Jido.AI.Plugins.ToolCalling,
           auto_execute: true, max_turns: 10}
        ]
      end

  Or use actions directly:

      # Call LLM with tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.CallWithTools, %{
        prompt: "What's the weather in Tokyo?",
        tools: ["weather"]
      })

      # Execute a tool directly
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ExecuteTool, %{
        tool_name: "calculator",
        params: %{"operation" => "add", "a" => 5, "b" => 3}
      })

      # List available tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ListTools, %{})

  ## Tool Source

  Tools are supplied through plugin configuration (`tools:`) and stored in plugin state.
  The plugin passes these tool modules through action context for discovery/execution.

  ## Auto-Execution

  When `auto_execute: true`, the plugin will:

  1. Send prompt to LLM with available tools
  2. If LLM returns tool calls, execute them automatically
  3. Send tool results back to LLM
  4. Repeat until LLM provides final answer or max turns reached

  ## Model Resolution

  Uses `Jido.AI.resolve_model/1` for model aliases:
  * `:fast` - Quick model for simple tasks (default: `anthropic:claude-haiku-4-5`)
  * `:capable` - Capable model for complex tasks (default: `anthropic:claude-sonnet-4-20250514`)
  * Direct model specs also supported

  ## Architecture Notes

  **Direct ReqLLM Calls**: Calls `ReqLLM.Generation.generate_text/3` with
  `tools:` option directly, following the core design principle of Jido.AI.

  **Tool Integration**: Uses context-provided tool maps for discovery
  and `Jido.AI.Turn` for execution.

  **Tool Format**: Tools are converted to ReqLLM format via
  `Jido.AI.ToolAdapter.from_actions/1`.
  """

  use Jido.Plugin,
    name: "tool_calling",
    state_key: :tool_calling,
    actions: [
      Jido.AI.Actions.ToolCalling.CallWithTools,
      Jido.AI.Actions.ToolCalling.ExecuteTool,
      Jido.AI.Actions.ToolCalling.ListTools
    ],
    description: "Provides LLM tool/function calling capabilities",
    category: "ai",
    tags: ["tool-calling", "function-calling", "llm", "tools"],
    vsn: "1.0.0"

  alias Jido.AI.ToolAdapter

  @doc """
  Initialize plugin state when mounted to an agent.
  """
  @impl Jido.Plugin
  def mount(_agent, config) do
    tools = Map.get(config, :tools, [])
    tools_map = build_tools_map(tools)

    initial_state = %{
      default_model: Map.get(config, :default_model, :capable),
      default_max_tokens: Map.get(config, :default_max_tokens, 4096),
      default_temperature: Map.get(config, :default_temperature, 0.7),
      auto_execute: Map.get(config, :auto_execute, false),
      max_turns: Map.get(config, :max_turns, 10),
      tools: tools_map,
      available_tools: Map.keys(tools_map)
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for plugin state.

  Defines the structure and defaults for Tool Calling plugin state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable)")
        |> Zoi.default(:capable),
      default_max_tokens: Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(4096),
      default_temperature:
        Zoi.float(description: "Default sampling temperature (0.0-2.0)")
        |> Zoi.default(0.7),
      auto_execute:
        Zoi.boolean(description: "Automatically execute tool calls in multi-turn conversations")
        |> Zoi.default(false),
      max_turns:
        Zoi.integer(description: "Maximum conversation turns when auto_execute is true")
        |> Zoi.default(10),
      available_tools:
        Zoi.list(
          Zoi.string(description: "Registered tool name"),
          description: "List of available tools from registry"
        )
        |> Zoi.default([])
    })
  end

  @doc """
  Returns the signal router for this plugin.

  Maps signal patterns to action modules.
  """
  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"tool.call", Jido.AI.Actions.ToolCalling.CallWithTools},
      {"tool.execute", Jido.AI.Actions.ToolCalling.ExecuteTool},
      {"tool.list", Jido.AI.Actions.ToolCalling.ListTools}
    ]
  end

  @doc """
  Pre-routing hook for incoming signals.

  Currently returns :continue to allow normal routing.
  """
  @impl Jido.Plugin
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @doc """
  Transform the result returned from action execution.

  Currently passes through results unchanged.
  """
  @impl Jido.Plugin
  def transform_result(_action, result, _context) do
    result
  end

  @doc """
  Returns signal patterns this plugin responds to.
  """
  def signal_patterns do
    [
      "tool.call",
      "tool.execute",
      "tool.list"
    ]
  end

  # Private Functions

  defp build_tools_map(tools) when is_list(tools) do
    ToolAdapter.to_action_map(tools)
  end

  defp build_tools_map(tools) when is_map(tools), do: ToolAdapter.to_action_map(tools)
end
