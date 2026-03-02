defmodule Jido.AI.ModelAliases do
  @moduledoc """
  Shared model alias resolution for public AI facades and ReAct runtime config.
  """

  @type model_alias ::
          :fast | :capable | :thinking | :reasoning | :planning | :image | :embedding | atom()
  @type model_spec :: String.t()

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
  @spec model_aliases() :: %{model_alias() => model_spec()}
  def model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{}) |> normalize_model_aliases()
    Map.merge(@default_aliases, configured)
  end

  @doc """
  Resolves an alias atom to a provider model spec or passes through a model spec.
  """
  @spec resolve_model(model_alias() | model_spec()) :: model_spec()
  def resolve_model(model) when is_binary(model), do: model

  def resolve_model(model) when is_atom(model) do
    aliases = model_aliases()

    case Map.get(aliases, model) do
      nil ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(model)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases))}"

      spec ->
        spec
    end
  end

  defp normalize_model_aliases(aliases) when is_map(aliases), do: aliases
  defp normalize_model_aliases(_), do: %{}
end
