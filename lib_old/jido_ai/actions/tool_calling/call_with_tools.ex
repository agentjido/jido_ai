defmodule Jido.AI.Actions.ToolCalling.CallWithTools do
  @moduledoc """
  A Jido.Action for LLM calls with tool/function calling support.

  This action sends a prompt to an LLM with available tools, handles tool calls
  in the response, and optionally executes tools automatically for multi-turn
  conversations.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:capable`) or direct spec
  * `prompt` (required) - The user prompt to send to the LLM
  * `system_prompt` (optional) - System prompt to guide behavior
  * `tools` (optional) - List of tool names to include (default: all registered)
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds
  * `auto_execute` (optional) - Auto-execute tool calls (default: `false`)
  * `max_turns` (optional) - Max conversation turns with tools (default: `10`)

  ## Examples

      # Basic tool call
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.CallWithTools, %{
        prompt: "What's 5 + 3?",
        tools: ["calculator"]
      })

      # With auto-execution
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.CallWithTools, %{
        prompt: "Calculate 15 * 7",
        auto_execute: true
      })
  """
  use Jido.Action,
    # Dialyzer has incomplete PLT information about req_llm dependencies
    name: "tool_calling_call_with_tools",
    description: "Send an LLM request with tool calling support",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :capable) or direct spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        tools:
          Zoi.list(Zoi.string(),
            description: "List of tool names to include (default: all registered)"
          )
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.min(1) |> Zoi.default(4096),
        temperature:
          Zoi.float(description: "Sampling temperature (0.0-2.0)")
          |> Zoi.min(0)
          |> Zoi.max(2)
          |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.min(1) |> Zoi.optional(),
        auto_execute:
          Zoi.boolean(description: "Automatically execute tool calls in multi-turn conversation")
          |> Zoi.default(false),
        max_turns:
          Zoi.integer(description: "Maximum conversation turns when auto_execute is true")
          |> Zoi.default(10)
      })

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["tool-calling", "llm", "function-calling"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  alias Jido.AI.ActionInput
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Validation
  alias Jido.AI.Actions.Helpers

  @defaults %{
    model: [:default_model, :model],
    max_tokens: [:default_max_tokens],
    temperature: [:default_temperature],
    system_prompt: [:default_system_prompt, :system_prompt],
    auto_execute: [:auto_execute],
    max_turns: [:max_turns]
  }

  @impl Jido.Action
  def run(params, context) do
    context = ActionInput.context(context)

    with :ok <- validate_explicit_max_turns(params),
         {:ok, params} <-
           ActionInput.parse(schema(), params, context, @defaults, [:chat, :tool_calling]),
         {:ok, params} <- Helpers.validate_and_sanitize_input(params),
         {:ok, max_turns} <- Validation.validate_max_turns(params.max_turns),
         {:ok, model} <- Helpers.resolve_model(params[:model], :capable),
         {:ok, messages} <-
           ReqLLM.Context.normalize(
             params.prompt,
             if(params[:system_prompt], do: [system_prompt: params.system_prompt], else: [])
           ),
         {:ok, options} <- ActionInput.options(params, context) do
      tools = context |> ActionInput.tools() |> ToolAdapter.to_action_map()
      tools = if is_list(params[:tools]), do: Map.take(tools, params.tools), else: tools

      definitions =
        tools
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {name, action} -> ToolAdapter.from_action(action, name: name) end)

      state = %{
        messages: messages.messages,
        model: model,
        options: Keyword.put(options, :tools, definitions),
        tools: tools,
        timeout: params[:timeout],
        max_turns: max_turns,
        auto_execute: params.auto_execute,
        round: 0,
        turn: nil,
        usage: %{},
        failure: nil
      }

      Jido.Exec.run(Jido.AI.Actions.ToolCalling.ModelFlow, state, context)
    end
  end

  defp validate_explicit_max_turns(params) when is_map(params) do
    case Map.fetch(params, :max_turns) do
      {:ok, max_turns} -> validate_max_turns_value(max_turns)
      :error -> validate_optional_string_max_turns(params)
    end
  end

  defp validate_explicit_max_turns(_params), do: :ok

  defp validate_optional_string_max_turns(params) do
    case Map.fetch(params, "max_turns") do
      {:ok, max_turns} -> validate_max_turns_value(max_turns)
      :error -> :ok
    end
  end

  defp validate_max_turns_value(max_turns) do
    case Validation.validate_max_turns(max_turns) do
      {:ok, _max_turns} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
