defmodule ReqAI.Provider.Utils do
  @moduledoc """
  Shared utilities for provider implementations.

  Contains common functions used across multiple providers to eliminate
  duplication and ensure consistency.

  ## Examples

      iex> ReqAI.Provider.Utils.normalize_messages("Hello world")
      [%{role: "user", content: "Hello world"}]

      iex> messages = [%{role: "user", content: "Hi"}]
      iex> ReqAI.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hi"}]

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"claude-3-haiku" => %{}, "claude-3-opus" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "claude-3-haiku"
  """

  @doc """
  Normalizes various prompt formats into a standardized messages list.

  ## Parameters

  - `prompt` - Can be a string, list of messages, or any other type that can be converted to string

  ## Returns

  A list of message maps with `:role` and `:content` keys.

  ## Examples

      iex> ReqAI.Provider.Utils.normalize_messages("What is the weather?")
      [%{role: "user", content: "What is the weather?"}]

      iex> messages = [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]
      iex> ReqAI.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]

      iex> ReqAI.Provider.Utils.normalize_messages(123)
      [%{role: "user", content: "123"}]
  """
  @spec normalize_messages(binary() | list() | term()) :: [map()]
  def normalize_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  def normalize_messages(messages) when is_list(messages) do
    messages
  end

  def normalize_messages(prompt) do
    [%{role: "user", content: to_string(prompt)}]
  end

  @doc """
  Gets the default model for a provider spec.

  Falls back to the first available model if no default is specified.

  ## Parameters

  - `spec` - Provider spec struct with `:default_model` and `:models` fields

  ## Returns

  The default model string, or `nil` if no models are available.

  ## Examples

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"model-a" => %{}, "model-b" => %{}}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      "model-a"

      iex> spec = %{default_model: nil, models: %{}}
      iex> ReqAI.Provider.Utils.default_model(spec)
      nil
  """
  @spec default_model(map()) :: binary() | nil
  def default_model(spec) do
    spec.default_model ||
      case Map.keys(spec.models) do
        [first_model | _] -> first_model
        [] -> nil
      end
  end
end
