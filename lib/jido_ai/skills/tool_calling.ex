# Ensure actions are compiled before the skill
require Jido.AI.Skills.ToolCalling.Actions.CallWithTools
require Jido.AI.Skills.ToolCalling.Actions.ExecuteTool
require Jido.AI.Skills.ToolCalling.Actions.ListTools

defmodule Jido.AI.Skills.ToolCalling do
  @moduledoc """
  A Jido.Skill providing LLM tool/function calling capabilities.

  This skill enables LLMs to call registered tools as functions during generation,
  with support for automatic tool execution and multi-turn conversations.

  ## Actions

  * `CallWithTools` - Send prompt to LLM with available tools, handle tool calls
  * `ExecuteTool` - Directly execute a tool by name with parameters
  * `ListTools` - List all available tools with their schemas

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        skills: [
          {Jido.AI.Skills.ToolCalling,
           auto_execute: true, max_turns: 10}
        ]
      end

  Or use actions directly:

      # Call LLM with tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.CallWithTools, %{
        prompt: "What's the weather in Tokyo?",
        tools: ["weather"]
      })

      # Execute a tool directly
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ExecuteTool, %{
        tool_name: "calculator",
        params: %{"operation" => "add", "a" => 5, "b" => 3}
      })

      # List available tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ListTools, %{})

  ## Tool Registry

  Tools are managed through `Jido.AI.Tools.Registry`:

  - **Actions** - Jido.Action modules registered as tools
  - All actions are executed via `Jido.Exec.run/3` for consistent validation

  ## Auto-Execution

  When `auto_execute: true`, the skill will:

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

  **Registry Integration**: Uses `Jido.AI.Tools.Registry` for tool discovery
  and `Jido.AI.Tools.Executor` for execution.

  **Tool Format**: Tools are converted to ReqLLM format via
  `Registry.to_reqllm_tools/0`.
  """

  use Jido.Skill,
    name: "tool_calling",
    state_key: :tool_calling,
    actions: [
      Jido.AI.Skills.ToolCalling.Actions.CallWithTools,
      Jido.AI.Skills.ToolCalling.Actions.ExecuteTool,
      Jido.AI.Skills.ToolCalling.Actions.ListTools
    ],
    description: "Provides LLM tool/function calling capabilities",
    category: "ai",
    tags: ["tool-calling", "function-calling", "llm", "tools"],
    vsn: "1.0.0"

  alias Jido.AI.Tools.Registry

  @doc """
  Initialize skill state when mounted to an agent.
  """
  @impl Jido.Skill
  def mount(_agent, config) do
    # Ensure registry is started
    Registry.ensure_started()

    initial_state = %{
      default_model: Map.get(config, :default_model, :capable),
      default_max_tokens: Map.get(config, :default_max_tokens, 4096),
      default_temperature: Map.get(config, :default_temperature, 0.7),
      auto_execute: Map.get(config, :auto_execute, false),
      max_turns: Map.get(config, :max_turns, 10),
      available_tools: list_available_tools()
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for skill state.

  Defines the structure and defaults for Tool Calling skill state.
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
          Zoi.map(description: "Tool information with :name and :type keys"),
          description: "List of available tools from registry"
        )
        |> Zoi.default([])
    })
  end

  @doc """
  Returns the signal router for this skill.

  Maps signal patterns to action modules.
  """
  @impl Jido.Skill
  def router(_config) do
    [
      {"tool.call", Jido.AI.Skills.ToolCalling.Actions.CallWithTools},
      {"tool.execute", Jido.AI.Skills.ToolCalling.Actions.ExecuteTool},
      {"tool.list", Jido.AI.Skills.ToolCalling.Actions.ListTools}
    ]
  end

  @doc """
  Pre-routing hook for incoming signals.

  Currently returns :continue to allow normal routing.
  """
  @impl Jido.Skill
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @doc """
  Transform the result returned from action execution.

  Currently passes through results unchanged.
  """
  @impl Jido.Skill
  def transform_result(_action, result, _context) do
    result
  end

  @doc """
  Returns signal patterns this skill responds to.
  """
  def signal_patterns do
    [
      "tool.call",
      "tool.execute",
      "tool.list"
    ]
  end

  # Private Functions

  defp list_available_tools do
    Registry.ensure_started()

    Registry.list_all()
    |> Enum.map(fn {name, type, _module} ->
      %{name: name, type: type}
    end)
  end
end
