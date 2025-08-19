defmodule JidoWorkbench.LLMKeys do
  @moduledoc """
  GenServer that manages LLM API keys loaded from environment variables.
  Serves as the source of truth for environment-level API keys.

  This needs to be replaced by Jido.AI.Keyring
  """

  use GenServer
  require Logger

  @settings [
    %{
      group: :llm,
      name: "Anthropic API Key",
      description: "API key for Claude and other Anthropic language models",
      key: :anthropic,
      type: :string,
      default: "",
      config_path: [:instructor, :anthropic, :api_key],
      session_key: "anthropic_api_key",
      env_var: "ANTHROPIC_API_KEY",
      signup_url: "https://console.anthropic.com",
      docs_url: "https://docs.anthropic.com/claude/docs/getting-access-to-claude",
      help_text: """
      You can get an API key by signing up at console.anthropic.com.
      Anthropic's Claude is a state-of-the-art language model known for its strong reasoning capabilities.
      """
    },
    %{
      group: :llm,
      name: "OpenAI API Key",
      description: "API key for GPT-4, GPT-3.5, and other OpenAI models",
      key: :openai,
      type: :string,
      default: "",
      config_path: [:openai, :api_key],
      session_key: "openai_api_key",
      env_var: "OPENAI_API_KEY",
      signup_url: "https://platform.openai.com/signup",
      docs_url: "https://platform.openai.com/docs/quickstart",
      help_text: """
      You can get an API key by signing up at platform.openai.com.
      OpenAI's GPT models are widely used for various AI tasks and natural language processing.
      """
    },
    %{
      group: :llm,
      name: "OpenRouter API Key",
      description: "API key for accessing multiple LLM providers through OpenRouter",
      key: :openrouter,
      type: :string,
      default: "",
      config_path: [:openrouter, :api_key],
      session_key: "openrouter_api_key",
      env_var: "OPENROUTER_API_KEY",
      signup_url: "https://openrouter.ai/keys",
      docs_url: "https://openrouter.ai/docs",
      help_text: """
      You can get an API key by signing up at openrouter.ai.
      OpenRouter provides unified access to multiple LLM providers including Anthropic, OpenAI, Google and more.
      """
    }
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Logger.info("Initializing LLM keys from environment")

    # Load environment variables
    env = Dotenvy.source!([".env", System.get_env()])

    # Extract only the LLM keys we care about
    keys =
      Enum.reduce(@settings, %{}, fn setting, acc ->
        value = Map.get(env, setting.env_var, setting.default)
        Map.put(acc, setting.key, value)
      end)

    # Log which keys were loaded (without values)
    loaded_keys = Map.keys(keys)
    Logger.info("Loaded LLM keys: #{inspect(loaded_keys)}")

    {:ok, keys}
  end

  @doc """
  Returns the list of available LLM key settings.
  """
  def settings, do: @settings

  @doc """
  Gets a key from the environment-level storage.
  """
  def get_env_key(key_type) when is_atom(key_type) do
    GenServer.call(__MODULE__, {:get_key, key_type})
  end

  @impl true
  def handle_call({:get_key, key_type}, _from, state) do
    {:reply, Map.get(state, key_type), state}
  end

  @doc """
  Validates if a key exists and is non-empty.
  """
  def has_valid_key?(nil), do: false
  def has_valid_key?(""), do: false
  def has_valid_key?(key) when is_binary(key), do: true
  def has_valid_key?(_), do: false

  @doc """
  Tests if a key is valid by making an API request.
  Returns {:ok, message} if valid, {:error, message} if invalid.
  """
  def test_key(key_type, key) when is_atom(key_type) do
    case key_type do
      :anthropic -> validate_anthropic_key(key)
      :openai -> validate_openai_key(key)
      _ -> {:error, "Unknown key type: #{inspect(key_type)}"}
    end
  end

  defp validate_anthropic_key(key) do
    case HTTPoison.get("https://api.anthropic.com/v1/models", [
           {"x-api-key", key},
           {"anthropic-version", "2023-06-01"}
         ]) do
      {:ok, %{status_code: 200}} -> {:ok, "Valid Anthropic API key"}
      {:ok, %{status_code: 401}} -> {:error, "Invalid Anthropic API key"}
      _ -> {:error, "Could not validate Anthropic API key"}
    end
  end

  defp validate_openai_key(key) do
    case HTTPoison.get("https://api.openai.com/v1/models", [
           {"Authorization", "Bearer #{key}"}
         ]) do
      {:ok, %{status_code: 200}} -> {:ok, "Valid OpenAI API key"}
      {:ok, %{status_code: 401}} -> {:error, "Invalid OpenAI API key"}
      _ -> {:error, "Could not validate OpenAI API key"}
    end
  end
end
