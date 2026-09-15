defmodule Jido.AI.Plugins.Chat do
  @moduledoc """
  Chat and tool defaults for explicit core Agent routes.

  Declare keyword options and a domain result field with `into: :result`.
  Routes returned by `signal_routes/1` use the capability's committed defaults.
  Tools may be supplied by name or as Action modules. `tool_policy` is retained
  as descriptive state; it is not an execution authorization rule.
  """
  use Jido.Plugin, agent: Jido.AI.Plugins.Chat.Agent

  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  @routes [
    {"chat.message", CallWithTools},
    {"chat.simple", Chat},
    {"chat.complete", Complete},
    {"chat.embed", Embed},
    {"chat.generate_object", GenerateObject},
    {"chat.execute_tool", ExecuteTool},
    {"chat.list_tools", ListTools}
  ]
  @defaults %{
    default_model: :capable,
    default_max_tokens: 4096,
    default_temperature: 0.7,
    default_system_prompt: nil,
    auto_execute: true,
    max_turns: 10,
    tool_policy: :allow_all,
    tools: %{},
    available_tools: []
  }

  def name, do: "chat"
  def description, do: "Provides conversational AI with built-in tool calling"
  def category, do: "ai"
  def tags, do: ["chat", "conversation", "tool-calling", "llm"]
  def vsn, do: "2.0.0"
  def state_key, do: :chat
  def actions, do: Enum.map(@routes, &elem(&1, 1))
  def signal_patterns, do: Enum.map(@routes, &elem(&1, 0))

  def signal_routes(_config),
    do: Enum.map(signal_patterns(), &{&1, Jido.AI.Actions.Chat.RunCapability})

  def schema, do: state_schema(@defaults) |> Zoi.default(@defaults)

  @doc false
  def agent_state_spec(opts) do
    supported = Map.keys(@defaults) -- [:available_tools]

    Jido.AI.PluginConfig.validate!(opts, [:into | supported], "Chat")

    into = Keyword.get(opts, :into, :result)

    unless is_atom(into) and not is_nil(into),
      do: raise(ArgumentError, "into must be a field atom")

    tools = Jido.AI.ToolAdapter.to_action_map(Keyword.get(opts, :tools, []))

    values =
      opts
      |> Keyword.delete(:into)
      |> Map.new()
      |> Map.put(:tools, tools)
      |> Map.put(:available_tools, Enum.sort(Map.keys(tools)))

    case Zoi.parse(schema(), values) do
      {:ok, defaults} -> {:chat, state_schema(defaults) |> Zoi.default(defaults)}
      {:error, errors} -> raise ArgumentError, "Invalid Chat defaults: #{inspect(errors)}"
    end
  end

  @doc false
  def prepare_input(preparation, opts) do
    binding =
      if action =
           Enum.find_value(@routes, fn {signal, action} ->
             if signal == preparation.signal.type, do: action
           end) do
        %{
          action: action,
          key: :chat,
          into: Keyword.get(opts, :into, :result),
          defaults: preparation.plugin_state
        }
      end

    {:ok, binding}
  end

  defp state_schema(defaults) do
    Zoi.object(%{
      default_model: Zoi.any() |> Zoi.default(defaults.default_model),
      default_max_tokens: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.default_max_tokens),
      default_temperature: Zoi.float() |> Zoi.min(0) |> Zoi.max(2) |> Zoi.default(defaults.default_temperature),
      default_system_prompt: Zoi.string() |> Zoi.nullable() |> Zoi.default(defaults.default_system_prompt),
      auto_execute: Zoi.boolean() |> Zoi.default(defaults.auto_execute),
      max_turns: Zoi.integer() |> Zoi.min(0) |> Zoi.default(defaults.max_turns),
      tool_policy: Zoi.atom() |> Zoi.default(defaults.tool_policy),
      tools: Zoi.map() |> Zoi.default(defaults.tools),
      available_tools: Zoi.list(Zoi.string()) |> Zoi.default(defaults.available_tools)
    })
  end
end
