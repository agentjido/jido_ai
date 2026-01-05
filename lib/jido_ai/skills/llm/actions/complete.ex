defmodule Jido.AI.Skills.LLM.Actions.Complete do
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
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Complete, %{
        prompt: "The capital of France is"
      })

      # With custom settings
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Complete, %{
        model: :capable,
        prompt: "Elixir is a functional programming language",
        max_tokens: 500,
        temperature: 0.5
      })
  """

  use Jido.Action,
    name: "llm_complete",
    description: "Complete text using an LLM without system prompts",
    category: "ai",
    tags: ["llm", "completion", "generation"],
    vsn: "1.0.0",
    schema: [
      model: [
        type: :string,
        required: false,
        doc: "Model spec (e.g., 'anthropic:claude-haiku-4-5') or alias (e.g., :fast)"
      ],
      prompt: [
        type: :string,
        required: true,
        doc: "The text prompt to complete"
      ],
      max_tokens: [
        type: :integer,
        required: false,
        default: 1024,
        doc: "Maximum tokens to generate"
      ],
      temperature: [
        type: :float,
        required: false,
        default: 0.7,
        doc: "Sampling temperature (0.0-2.0)"
      ],
      timeout: [
        type: :integer,
        required: false,
        doc: "Request timeout in milliseconds"
      ]
    ]

  alias Jido.AI.Config
  alias Jido.AI.Helpers

  @doc """
  Executes the completion action.

  ## Returns

  * `{:ok, result}` - Successful response with `text`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        text: "The completed text",
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
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, messages} <- build_messages(params[:prompt]),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, opts) do
      {:ok, format_result(response, model)}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:fast)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_messages(prompt) do
    Helpers.build_messages(prompt, [])
  end

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp format_result(response, model) do
    %{
      text: extract_text(response),
      model: model,
      usage: extract_usage(response)
    }
  end

  defp extract_text(%{message: %{content: content}}) when is_binary(content), do: content

  defp extract_text(%{message: %{content: content}}) when is_list(content) do
    content
    |> Enum.filter(fn part ->
      case part do
        %{type: :text} -> true
        _ -> false
      end
    end)
    |> Enum.map_join("", fn
      %{text: text} -> text
      _ -> ""
    end)
  end

  defp extract_text(_), do: ""

  defp extract_usage(%{usage: usage}) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
  end

  defp extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
end
