defmodule Jido.AI.Provider.Util.Options do
  @moduledoc """
  Utilities for merging and handling provider options.
  """

  alias Jido.AI.{ContentPart, Message, Model}

  @default_chat_completion_opts ~w(
    model
    messages
    frequency_penalty
    max_completion_tokens
    max_tokens
    n
    presence_penalty
    response_format
    seed
    stop
    temperature
    top_p
    user
  )a

  @doc """
  Returns the default set of chat completion options.
  """
  @spec default() :: [
          :frequency_penalty
          | :max_completion_tokens
          | :max_tokens
          | :messages
          | :model
          | :n
          | :presence_penalty
          | :response_format
          | :seed
          | :stop
          | :temperature
          | :top_p
          | :user,
          ...
        ]
  def default, do: @default_chat_completion_opts

  @doc """
  Merges Model configuration with request options.
  Model options are used as defaults, opts take precedence.
  """
  @spec merge_model_options(module(), Model.t(), keyword()) :: keyword()
  def merge_model_options(provider_module, %Model{} = model, opts) do
    # Get API key from model's provider configuration or opts
    api_key =
      Keyword.get(opts, :api_key) ||
        Jido.AI.config([model.provider, :api_key])

    # Get base URL from provider module
    base_url = provider_module.api_url()

    model_opts =
      []
      |> maybe_put(:temperature, model.temperature)
      |> maybe_put(:max_tokens, model.max_tokens)
      |> maybe_put(:max_retries, model.max_retries)
      |> maybe_put(:api_key, api_key)
      |> maybe_put(:url, base_url <> "/chat/completions")

    # Provided opts take precedence over model defaults
    Keyword.merge(model_opts, opts)
  end

  @doc """
  Merges provider-specific options from multiple levels with correct precedence.

  Precedence (highest to lowest):
  1. Content-part level metadata
  2. Message level metadata
  3. Function level opts parameter
  4. Model defaults (handled in merge_model_options)

  ## Parameters

    * `model` - The Model struct (for provider context)
    * `prompt` - String or list of Message structs
    * `function_opts` - Options passed to generate_text/stream_text functions
    * `provider_opts` - Existing provider options from function level

  ## Examples

      iex> merge_provider_options(model, "hello", [], %{})
      %{}

      iex> messages = [%Message{content: "hi", metadata: %{provider_options: %{openai: %{temp: 0.5}}}}]
      iex> merge_provider_options(model, messages, [], %{})
      %{openai: %{temp: 0.5}}

  """
  @spec merge_provider_options(Model.t(), String.t() | [Message.t()], keyword(), map()) :: map()
  def merge_provider_options(%Model{provider: _provider}, prompt, function_opts, base_provider_opts) do
    # Start with base provider options (from function level or model)
    acc = base_provider_opts

    # Extract provider options from function level opts
    function_provider_opts = Keyword.get(function_opts, :provider_options, %{})
    acc = deep_merge_provider_options(acc, function_provider_opts)

    # Extract provider options from messages (if prompt is message list)
    case prompt do
      messages when is_list(messages) ->
        messages
        |> Enum.reduce(acc, fn message, acc_opts ->
          message_opts = Message.provider_options(message)
          acc_opts = deep_merge_provider_options(acc_opts, message_opts)

          # Extract content part options if content is a list
          case message.content do
            content_parts when is_list(content_parts) ->
              Enum.reduce(content_parts, acc_opts, fn part, part_acc_opts ->
                part_opts = ContentPart.provider_options(part)
                deep_merge_provider_options(part_acc_opts, part_opts)
              end)

            _ ->
              acc_opts
          end
        end)

      _ ->
        acc
    end
  end

  # Deep merge provider options with proper precedence
  @spec deep_merge_provider_options(map(), map()) :: map()
  defp deep_merge_provider_options(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_val, override_val ->
      case {base_val, override_val} do
        {base_map, override_map} when is_map(base_map) and is_map(override_map) ->
          deep_merge_provider_options(base_map, override_map)

        {_, override_val} ->
          override_val
      end
    end)
  end

  @spec deep_merge_provider_options(term(), term()) :: term()
  defp deep_merge_provider_options(_base, override), do: override

  @doc """
  Helper function to conditionally add JSON mode based on provider support.
  """
  @spec maybe_add_json_mode(keyword(), module()) :: keyword()
  def maybe_add_json_mode(opts, provider_module) do
    if provider_module.supports_json_mode?() do
      Keyword.put(opts, :response_format, %{type: "json_object"})
    else
      opts
    end
  end

  @spec maybe_put(Keyword.t(), :api_key | :max_retries | :max_tokens | :temperature | :url, term()) :: Keyword.t()
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
