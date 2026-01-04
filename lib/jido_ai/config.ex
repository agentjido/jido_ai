defmodule Jido.AI.Config do
  @moduledoc """
  Configuration helpers for ReqLLM provider settings.

  This module provides configuration management for Jido.AI, including:
  - Provider configuration (API keys, base URLs)
  - Model aliases (semantic names like `:fast`, `:capable`)
  - Default settings (temperature, max_tokens)

  **Important**: This module configures ReqLLM settings but does NOT wrap ReqLLM.
  All LLM calls should go directly to ReqLLM functions.

  ## Configuration

  Configure in your application's `config.exs` or `runtime.exs`:

      config :jido_ai,
        providers: %{
          openai: [api_key: {:system, "OPENAI_API_KEY"}],
          anthropic: [api_key: {:system, "ANTHROPIC_API_KEY"}],
          google: [api_key: {:system, "GOOGLE_API_KEY"}],
          ollama: [base_url: "http://localhost:11434"]
        },
        model_aliases: %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514",
          reasoning: "anthropic:claude-sonnet-4-20250514"
        },
        defaults: %{
          temperature: 0.7,
          max_tokens: 1024
        }

  ## Usage

      # Resolve a model alias to ReqLLM model spec
      Jido.AI.Config.resolve_model(:fast)
      # => "anthropic:claude-haiku-4-5"

      # Pass through direct model specs
      Jido.AI.Config.resolve_model("openai:gpt-4")
      # => "openai:gpt-4"

      # Get provider configuration
      Jido.AI.Config.get_provider(:anthropic)
      # => [api_key: "sk-ant-..."]

      # Get default settings
      Jido.AI.Config.defaults()
      # => %{temperature: 0.7, max_tokens: 1024}
  """

  @type provider :: :openai | :anthropic | :google | :ollama | atom()
  @type model_alias :: :fast | :capable | :reasoning | atom()
  @type model_spec :: String.t()
  @type provider_config :: keyword()

  # Default model aliases
  @default_aliases %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514"
  }

  # Default settings
  @default_settings %{
    temperature: 0.7,
    max_tokens: 1024
  }

  @doc """
  Retrieves configuration for a specific provider.

  Returns the provider configuration with environment variables resolved.
  Returns an empty list if the provider is not configured.

  ## Arguments

    * `provider` - Provider atom (`:openai`, `:anthropic`, `:google`, `:ollama`)

  ## Returns

    A keyword list of provider configuration with environment variables resolved.

  ## Examples

      iex> Jido.AI.Config.get_provider(:anthropic)
      [api_key: "sk-ant-..."]

      iex> Jido.AI.Config.get_provider(:unknown)
      []
  """
  @spec get_provider(provider()) :: provider_config()
  def get_provider(provider) when is_atom(provider) do
    providers = Application.get_env(:jido_ai, :providers, %{})

    case Map.get(providers, provider) do
      nil -> []
      config when is_list(config) -> resolve_env_vars(config)
      config when is_map(config) -> config |> Map.to_list() |> resolve_env_vars()
    end
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

      iex> Jido.AI.Config.resolve_model(:fast)
      "anthropic:claude-haiku-4-5"

      iex> Jido.AI.Config.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      iex> Jido.AI.Config.resolve_model(:unknown_alias)
      ** (ArgumentError) Unknown model alias: :unknown_alias
  """
  @spec resolve_model(model_alias() | model_spec()) :: model_spec()
  def resolve_model(model) when is_binary(model), do: model

  def resolve_model(model) when is_atom(model) do
    aliases = get_model_aliases()

    case Map.get(aliases, model) do
      nil ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(model)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases))}"

      spec ->
        spec
    end
  end

  @doc """
  Returns all configured model aliases merged with defaults.

  ## Returns

    A map of alias atoms to model spec strings.

  ## Examples

      iex> Jido.AI.Config.get_model_aliases()
      %{fast: "anthropic:claude-haiku-4-5", capable: "anthropic:claude-sonnet-4-20250514", ...}
  """
  @spec get_model_aliases() :: %{model_alias() => model_spec()}
  def get_model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{})
    Map.merge(@default_aliases, configured)
  end

  @doc """
  Returns the default settings merged with application configuration.

  ## Returns

    A map of default settings (temperature, max_tokens, etc.)

  ## Examples

      iex> Jido.AI.Config.defaults()
      %{temperature: 0.7, max_tokens: 1024}
  """
  @spec defaults() :: map()
  def defaults do
    configured = Application.get_env(:jido_ai, :defaults, %{})
    Map.merge(@default_settings, configured)
  end

  @doc """
  Returns a specific default setting value.

  ## Arguments

    * `key` - The setting key (e.g., `:temperature`, `:max_tokens`)
    * `fallback` - Optional fallback value if key is not found (default: `nil`)

  ## Returns

    The setting value or fallback.

  ## Examples

      iex> Jido.AI.Config.get_default(:temperature)
      0.7

      iex> Jido.AI.Config.get_default(:unknown, 42)
      42
  """
  @spec get_default(atom(), term()) :: term()
  def get_default(key, fallback \\ nil) when is_atom(key) do
    Map.get(defaults(), key, fallback)
  end

  @doc """
  Validates the current configuration.

  Checks that all required settings are present and valid. Returns `:ok` if
  valid, or `{:error, reasons}` with a list of validation errors.

  ## Returns

    * `:ok` - Configuration is valid
    * `{:error, [String.t()]}` - List of validation error messages

  ## Examples

      iex> Jido.AI.Config.validate()
      :ok
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    # Validate model aliases point to valid-looking specs
    aliases = get_model_aliases()

    alias_errors =
      Enum.flat_map(aliases, fn {alias_name, spec} ->
        if valid_model_spec?(spec) do
          []
        else
          ["Invalid model spec for alias #{inspect(alias_name)}: #{inspect(spec)}"]
        end
      end)

    # Validate defaults have valid types
    default_errors = validate_defaults()

    all_errors = alias_errors ++ default_errors

    if all_errors == [] do
      :ok
    else
      {:error, all_errors}
    end
  end

  # Private helpers

  defp resolve_env_vars(config) when is_list(config) do
    Enum.map(config, fn
      {key, {:system, env_var}} when is_binary(env_var) ->
        {key, System.get_env(env_var)}

      {key, {:system, env_var, default}} when is_binary(env_var) ->
        {key, System.get_env(env_var) || default}

      other ->
        other
    end)
  end

  defp valid_model_spec?(spec) when is_binary(spec) do
    # Valid specs have format "provider:model" or just "model"
    case String.split(spec, ":", parts: 2) do
      [_provider, _model] -> true
      [_model] -> true
      _ -> false
    end
  end

  defp valid_model_spec?(_), do: false

  defp validate_defaults do
    defaults = defaults()

    validators = [
      {:temperature, &validate_temperature/1},
      {:max_tokens, &validate_max_tokens/1}
    ]

    Enum.flat_map(validators, fn {key, validator} ->
      defaults |> Map.get(key) |> validator.()
    end)
  end

  defp validate_temperature(nil), do: []
  defp validate_temperature(t) when is_number(t) and t >= 0 and t <= 2, do: []
  defp validate_temperature(t), do: ["Invalid temperature: #{inspect(t)}. Must be a number between 0 and 2."]

  defp validate_max_tokens(nil), do: []
  defp validate_max_tokens(t) when is_integer(t) and t > 0, do: []
  defp validate_max_tokens(t), do: ["Invalid max_tokens: #{inspect(t)}. Must be a positive integer."]
end
