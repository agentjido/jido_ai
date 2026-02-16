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
    category: "ai",
    tags: ["llm", "chat", "generation"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct model spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
        temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Security
  alias Jido.AI.Actions.Helpers
  alias ReqLLM.Context

  @doc """
  Executes the chat action.

  ## Returns

  * `{:ok, result}` - Successful response with `text`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        text: "The LLM's response text",
        model: "anthropic:claude-haiku-4-5",
        usage: %{
          input_tokens: 10,
          output_tokens: 25,
          total_tokens: 35
        }
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, validated_params} <- Helpers.validate_and_sanitize_input(params),
         {:ok, model} <- Helpers.resolve_model(validated_params[:model], :fast),
         {:ok, req_context} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         opts = Helpers.build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, req_context.messages, opts) do
      {:ok, format_result(response, model)}
    else
      {:error, reason} -> {:error, sanitize_error_for_user(reason)}
    end
  end

  # Private Functions

  defp sanitize_error_for_user(error) when is_struct(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

  defp build_messages(prompt, nil) do
    Context.normalize(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Context.normalize(prompt, system_prompt: system_prompt)
  end

  defp format_result(response, model) do
    %{
      text: Helpers.extract_text(response),
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end
end
