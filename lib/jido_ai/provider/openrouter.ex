defmodule Jido.AI.Provider.OpenRouter do
  @moduledoc """
  OpenRouter provider implementation for text generation.

  OpenRouter acts as a proxy for multiple AI providers, providing
  unified access to models from various companies.

  ## Usage

      iex> Jido.AI.Provider.OpenRouter.generate_text(
      ...>   "anthropic/claude-3.5-sonnet",
      ...>   "Hello, world!"
      ...> )
      {:ok, "Hello! How can I help you today?"}

  """

  use Jido.AI.Provider.Macro,
    json: "openrouter.json",
    base_url: "https://openrouter.ai/api/v1"

  alias Jido.AI.Provider.Util.Options

  @impl true
  def supports_json_mode?, do: true

  @impl true
  def chat_completion_opts do
    Options.default() ++ [:include_reasoning, :thinking]
  end

  # Uses default implementation from Macro for generate_text/3
end
