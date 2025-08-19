defmodule Jido.AI.Provider.Anthropic do
  @moduledoc """
  Anthropic provider implementation for text generation.

  Provides access to Anthropic's Claude models including Claude 3.5 Sonnet,
  Claude 3 Opus, and other models in the Claude family.

  ## Usage

      iex> Jido.AI.Provider.Anthropic.generate_text(
      ...>   "claude-3-5-sonnet-20241022",
      ...>   "Hello, world!"
      ...> )
      {:ok, "Hello! How can I help you today?"}

  """

  use Jido.AI.Provider.Macro,
    json: "anthropic.json",
    base_url: "https://api.anthropic.com/v1"

  @impl true
  def supports_json_mode?, do: true

  @impl true
  def stream_event_type, do: :anthropic
end
