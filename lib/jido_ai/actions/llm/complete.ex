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
    category: "ai",
    tags: ["llm", "completion", "generation"],
    vsn: "1.0.0",
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

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Error.Sanitize
  alias ReqLLM.Context

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
  def run(params, context) do
    params = apply_context_defaults(params, context)

    with {:ok, validated_params} <- Helpers.validate_and_sanitize_input(params),
         {:ok, model} <- Helpers.resolve_model(validated_params[:model], :fast),
         {:ok, req_context} <- build_messages(validated_params[:prompt]),
         opts = Helpers.build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, req_context.messages, opts) do
      {:ok, format_result(response, model)}
    else
      {:error, reason} -> {:error, sanitize_error_for_user(reason)}
    end
  end

  # Private Functions

  defp build_messages(prompt) do
    Context.normalize(prompt, [])
  end

  defp sanitize_error_for_user(error) when is_struct(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    max_tokens_default =
      first_present([
        context[:default_max_tokens],
        plugin_default(context, :default_max_tokens)
      ])

    temperature_default =
      first_present([
        context[:default_temperature],
        plugin_default(context, :default_temperature)
      ])

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:max_tokens, max_tokens_default, provided)
    |> put_default_param(:temperature, temperature_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :chat, key]),
      get_in(context, [:plugin_state, :llm, key]),
      get_in(context, [:state, :chat, key]),
      get_in(context, [:state, :llm, key]),
      get_in(context, [:agent, :state, :chat, key]),
      get_in(context, [:agent, :state, :llm, key])
    ])
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

  defp format_result(response, model) do
    %{
      text: Helpers.extract_text(response),
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end
end
