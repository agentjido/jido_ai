defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI provides a unified interface for AI interactions, built on ReqLLM and
  integrated with the Jido action framework.

  ## Features

  - Text generation with any supported LLM provider
  - Structured output generation with schema validation
  - Streaming responses
  - Action-based AI workflows
  - Splode-based error handling

  ## Model Aliases

  Use semantic model aliases instead of hardcoded model strings:

      Jido.AI.resolve_model(:fast)      # => "anthropic:claude-haiku-4-5"
      Jido.AI.resolve_model(:capable)   # => "anthropic:claude-sonnet-4-20250514"

  Configure custom aliases in your config:

      config :jido_ai,
        model_aliases: %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514"
        }

  ## Quick Start

      # Generate text
      {:ok, response} = Jido.AI.generate_text("anthropic:claude-haiku-4-5", "Hello!")

      # Generate structured output
      schema = Zoi.object(%{name: Zoi.string(), age: Zoi.integer()})
      {:ok, person} = Jido.AI.generate_object("openai:gpt-4", "Generate a person", schema)

  """

  @type model_alias :: :fast | :capable | :reasoning | :planning | atom()
  @type model_spec :: String.t()

  @default_aliases %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514",
    planning: "anthropic:claude-sonnet-4-20250514"
  }

  @doc """
  Returns all configured model aliases merged with defaults.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> aliases[:fast]
      "anthropic:claude-haiku-4-5"
  """
  @spec model_aliases() :: %{model_alias() => model_spec()}
  def model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{})
    Map.merge(@default_aliases, configured)
  end

  @doc """
  Resolves a model alias or passes through a direct model spec.

  Model aliases are atoms like `:fast`, `:capable`, `:reasoning` that map
  to full ReqLLM model specifications. Direct model specs (strings) are
  passed through unchanged.

  ## Arguments

    * `model` - Either a model alias atom or a direct model spec string

  ## Returns

    A ReqLLM model specification string.

  ## Examples

      iex> Jido.AI.resolve_model(:fast)
      "anthropic:claude-haiku-4-5"

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
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
end
