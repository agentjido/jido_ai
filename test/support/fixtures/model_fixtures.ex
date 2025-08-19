defmodule Jido.AI.Test.Fixtures.ModelFixtures do
  @moduledoc """
  Test fixtures for AI models.

  Provides short, descriptive functions for creating test models
  with consistent configurations across the test suite.
  """

  alias Jido.AI.Model

  @doc """
  Returns a GPT-4 model for testing.
  """
  def gpt4(opts \\ []) do
    %Model{
      provider: :openai,
      model: "gpt-4",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "gpt-4",
      name: "GPT-4",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2023-03",
      last_updated: "2024-01",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 128_000, output: 4096}
    }
  end

  @doc """
  Returns a GPT-4o model for testing.
  """
  def gpt4o(opts \\ []) do
    %Model{
      provider: :openai,
      model: "gpt-4o",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "gpt-4o",
      name: "GPT-4o",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-05",
      last_updated: "2024-05",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 128_000, output: 4096}
    }
  end

  @doc """
  Returns a Claude Sonnet model for testing.
  """
  def claude(opts \\ []) do
    %Model{
      provider: :anthropic,
      model: "claude-3-sonnet",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "claude-3-sonnet",
      name: "Claude 3 Sonnet",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-03",
      last_updated: "2024-03",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 200_000, output: 4096}
    }
  end

  @doc """
  Returns a Claude Opus model for testing.
  """
  def claude_opus(opts \\ []) do
    %Model{
      provider: :anthropic,
      model: "claude-3-opus-20240229",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "claude-3-opus-20240229",
      name: "Claude 3 Opus",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-02",
      last_updated: "2024-02",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 200_000, output: 4096}
    }
  end

  @doc """
  Returns a Gemini Pro model for testing.
  """
  def gemini(opts \\ []) do
    %Model{
      provider: :google,
      model: "gemini-pro",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "gemini-pro",
      name: "Gemini Pro",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2023-12",
      last_updated: "2024-01",
      modalities: %{input: [:text, :image], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 1_048_576, output: 8192}
    }
  end

  @doc """
  Returns a Mistral Large model for testing.
  """
  def mistral(opts \\ []) do
    %Model{
      provider: :mistral,
      model: "mistral-large",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3,
      id: "mistral-large",
      name: "Mistral Large",
      attachment: false,
      reasoning: true,
      supports_temperature: true,
      tool_call: true,
      knowledge: nil,
      release_date: "2024-02",
      last_updated: "2024-02",
      modalities: %{input: [:text], output: [:text]},
      open_weights: false,
      cost: nil,
      limit: %{context: 128_000, output: 4096}
    }
  end

  @doc """
  Returns a simple fake model for testing.
  """
  def fake(opts \\ []) do
    %Model{
      provider: :fake,
      model: opts[:model] || "fake-model",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3
    }
  end

  @doc """
  Returns a minimal model for testing.
  """
  def minimal(opts \\ []) do
    %Model{
      provider: opts[:provider] || :test,
      model: opts[:model] || "test-model",
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      max_retries: opts[:max_retries] || 3
    }
  end

  # Legacy format models for backward compatibility tests

  @doc """
  Returns a GPT-4 model configuration (legacy format).
  """
  def gpt4_legacy(opts \\ []) do
    %{
      provider: :openai,
      model: "gpt-4",
      api_key: opts[:api_key] || "test-openai-key",
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 1000
    }
  end

  @doc """
  Returns a Claude model configuration (legacy format).
  """
  def claude_legacy(opts \\ []) do
    %{
      provider: :anthropic,
      model: "claude-3-opus-20240229",
      api_key: opts[:api_key] || "test-anthropic-key",
      temperature: opts[:temperature] || 0.8,
      max_tokens: opts[:max_tokens] || 1500
    }
  end

  @doc """
  Returns a Gemini model configuration (legacy format).
  """
  def gemini_legacy(opts \\ []) do
    %{
      provider: :google,
      model: "gemini-pro",
      api_key: opts[:api_key] || "test-google-key",
      temperature: opts[:temperature] || 0.6,
      max_tokens: opts[:max_tokens] || 2000
    }
  end

  @doc """
  Returns a Mistral model configuration (legacy format).
  """
  def mistral_legacy(opts \\ []) do
    %{
      provider: :mistral,
      model: "mistral-large",
      api_key: opts[:api_key] || "test-mistral-key",
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 1200
    }
  end

  @doc """
  Returns a list of all test model configurations (legacy format).
  """
  def all_legacy_models do
    [gpt4_legacy(), claude_legacy(), gemini_legacy(), mistral_legacy()]
  end
end
