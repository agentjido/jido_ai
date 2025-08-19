defmodule Jido.AI.Provider.Google do
  @moduledoc """
  Google provider implementation for text generation.

  Provides access to Google's Gemini models including Gemini Pro,
  Gemini Flash, and other models in the Gemini family.

  ## Usage

      iex> Jido.AI.Provider.Google.generate_text(
      ...>   "gemini-1.5-pro",
      ...>   "Hello, world!"
      ...> )
      {:ok, "Hello! How can I help you today?"}

  """

  use Jido.AI.Provider.Macro,
    json: "google.json",
    base_url: "https://generativelanguage.googleapis.com/v1"
end
