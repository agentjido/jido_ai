defmodule Jido.AI.Actions.LLM.Complete do
  @moduledoc """
  A Jido.Action for simple text completion without system prompts.

  This action provides straightforward text completion using ReqLLM.
  Unlike `Chat`, it does not support system prompts - it simply completes
  the given prompt text.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:fast`, `:capable`) or direct spec
  * `prompt` (required) - The text prompt to complete
  * `max_tokens` (optional) - Maximum tokens to generate (default: `1024`)
  * `temperature` (optional) - Sampling temperature 0.0-2.0 (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic completion
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Complete, %{
        prompt: "The capital of France is"
      })

      # With custom settings
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Complete, %{
        model: :capable,
        prompt: "Elixir is a functional programming language",
        max_tokens: 500,
        temperature: 0.5
      })
  """

  use Jido.Action,
    name: "llm_complete",
    description: "Complete text using an LLM without system prompts",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct model spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The text prompt to complete"),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
        temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["llm", "completion", "generation"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context),
    do: Jido.AI.Actions.LLM.Request.run(:complete, __MODULE__, params, context)
end
