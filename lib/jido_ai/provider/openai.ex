defmodule Jido.AI.Provider.OpenAI do
  @moduledoc """
  OpenAI provider implementation for text generation.

  Provides access to OpenAI's GPT models including GPT-4, GPT-3.5-turbo,
  and other models in the OpenAI family.

  ## Usage

      iex> Jido.AI.Provider.OpenAI.generate_text(
      ...>   "gpt-4",
      ...>   "Hello, world!"
      ...> )
      {:ok, "Hello! How can I help you today?"}

  """

  use Jido.AI.Provider.Macro,
    json: "openai.json",
    base_url: "https://api.openai.com/v1"

  @impl true
  @spec supports_json_mode?() :: true
  def supports_json_mode?, do: true

  @impl true
  @spec stream_event_type() :: :openai
  def stream_event_type, do: :openai
end
