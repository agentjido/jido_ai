defmodule Jido.AI.ModelAliases do
  @moduledoc """
  Shared model alias resolution for public AI facades and ReAct runtime config.
  """

  @type model_alias ::
          :fast | :capable | :thinking | :reasoning | :planning | :image | :embedding | atom()

  @default_aliases %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    thinking: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514",
    planning: "anthropic:claude-sonnet-4-20250514",
    image: "openai:gpt-image-1",
    embedding: "openai:text-embedding-3-small"
  }

  @doc """
  Returns configured model aliases merged over built-in defaults.
  """
  @spec model_aliases() :: %{model_alias() => ReqLLM.model_input()}
  def model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{}) |> normalize_model_aliases()
    Map.merge(@default_aliases, configured)
  end

  @doc """
  Resolves an alias atom to a provider model spec.
  """
  @spec resolve_model(model_alias()) :: ReqLLM.model_input()
  def resolve_model(model) when is_atom(model) do
    aliases = model_aliases()

    case Map.get(aliases, model) do
      nil ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(model)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases))}"

      spec ->
        validate_alias_spec!(model, spec)
    end
  end

  defp normalize_model_aliases(aliases) when is_map(aliases), do: aliases
  defp normalize_model_aliases(_), do: %{}

  defp validate_alias_spec!(alias_name, spec) do
    cond do
      is_binary(spec) ->
        spec

      valid_reqllm_input_shape?(spec) ->
        validate_reqllm_model_input!(alias_name, spec)

      true ->
        raise_invalid_alias_spec!(alias_name, spec, "unsupported value shape")
    end
  end

  defp validate_reqllm_model_input!(alias_name, spec) do
    case ReqLLM.model(spec) do
      {:ok, _model} ->
        spec

      {:error, reason} ->
        raise_invalid_alias_spec!(alias_name, spec, format_reason(reason))
    end
  end

  defp valid_reqllm_input_shape?(%LLMDB.Model{}), do: true
  defp valid_reqllm_input_shape?(spec) when is_map(spec) and not is_struct(spec), do: true

  defp valid_reqllm_input_shape?({provider, model_id, provider_opts})
       when is_atom(provider) and is_binary(model_id) and is_list(provider_opts),
       do: true

  defp valid_reqllm_input_shape?({provider, provider_opts})
       when is_atom(provider) and is_list(provider_opts),
       do: true

  defp valid_reqllm_input_shape?(_), do: false

  defp raise_invalid_alias_spec!(alias_name, spec, detail) do
    raise ArgumentError,
          "Invalid model spec configured for alias #{inspect(alias_name)}: #{inspect(spec)}. " <>
            "Expected a valid ReqLLM model input. #{detail}"
  end

  defp format_reason(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_reason(reason), do: inspect(reason)
end
