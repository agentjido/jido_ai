defmodule ReqAI.Config do
  @moduledoc """
  Configuration management for ReqAI providers.

  Provides simple API key resolution for AI providers using environment variables.
  """

  @doc """
  Retrieves the API key for the specified provider.

  Looks up environment variables for the given provider and returns the first
  non-nil value found.

  ## Examples

      iex> System.put_env("ANTHROPIC_API_KEY", "sk-test")
      iex> ReqAI.Config.api_key(:anthropic)
      "sk-test"
      
      iex> ReqAI.Config.api_key(:nonexistent)
      nil

  """
  @spec api_key(atom()) :: String.t() | nil
  def api_key(:anthropic) do
    System.get_env("ANTHROPIC_API_KEY") || Application.get_env(:req_ai, :anthropic_api_key)
  end

  def api_key(:openai) do
    System.get_env("OPENAI_API_KEY") || Application.get_env(:req_ai, :openai_api_key)
  end

  def api_key(_provider), do: nil
end
