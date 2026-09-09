defmodule Jido.AI.Actions.LLM.Chat do
  @moduledoc """
  A Jido.Action for chat-style LLM interactions with optional system prompts.

  This action uses ReqLLM directly to generate chat-style responses from
  language models. It supports model aliases via `Jido.AI.resolve_model/1` and
  optional system prompts for conversation context.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:fast`, `:capable`) or direct spec (e.g., `"anthropic:claude-haiku-4-5"`)
  * `prompt` (required) - The user prompt to send to the LLM
  * `system_prompt` (optional) - System prompt to guide the LLM's behavior
  * `max_tokens` (optional) - Maximum tokens to generate (default: `1024`)
  * `temperature` (optional) - Sampling temperature 0.0-2.0 (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic chat
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        prompt: "What is Elixir?"
      })

      # With system prompt
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        model: :capable,
        prompt: "Explain GenServers",
        system_prompt: "You are an expert Elixir teacher.",
        temperature: 0.5
      })

      # Direct model spec
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
        model: "openai:gpt-4",
        prompt: "Hello!"
      })
  """

  use Jido.Action,
    name: "llm_chat",
    description: "Send a chat message to an LLM and get a response",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct model spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.min(1) |> Zoi.default(1024),
        temperature:
          Zoi.float(description: "Sampling temperature (0.0-2.0)")
          |> Zoi.min(0)
          |> Zoi.max(2)
          |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.min(1) |> Zoi.optional()
      })

  def category, do: "ai"
  def tags, do: ["llm", "chat", "generation"]
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context),
    do: Jido.AI.Actions.LLM.Request.run(:chat, __MODULE__, params, context)
end
