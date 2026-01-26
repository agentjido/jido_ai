defmodule Jido.AI.Accuracy.TestSupport.ReqLLMMock do
  @moduledoc """
  Mock for ReqLLM for testing accuracy modules.

  This mock provides deterministic responses without making actual API calls.
  Supports configurable responses, timeouts, and errors.
  """

  @type t :: %__MODULE__{
          responses: list(),
          call_count: non_neg_integer(),
          simulate_timeout: boolean(),
          simulate_error: term() | nil
        }

  defstruct [
    :responses,
    :call_count,
    :simulate_timeout,
    :simulate_error
  ]

  @doc """
  Creates a new mock with default responses.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      responses: Keyword.get(opts, :responses, default_responses()),
      call_count: 0,
      simulate_timeout: Keyword.get(opts, :simulate_timeout, false),
      simulate_error: Keyword.get(opts, :simulate_error, nil)
    }
  end

  @doc """
  Creates a mock that returns a specific response.
  """
  @spec with_response(String.t()) :: t()
  def with_response(content) do
    new(responses: [build_response(content)])
  end

  @doc """
  Creates a mock that returns multiple responses.
  """
  @spec with_responses(list(String.t())) :: t()
  def with_responses(contents) when is_list(contents) do
    responses = Enum.map(contents, &build_response/1)
    new(responses: responses)
  end

  @doc """
  Creates a mock that simulates a timeout.
  """
  @spec with_timeout() :: t()
  def with_timeout do
    new(simulate_timeout: true)
  end

  @doc """
  Creates a mock that simulates an error.
  """
  @spec with_error(term()) :: t()
  def with_error(reason) do
    new(simulate_error: reason)
  end

  # Public API for tests (not implementing full ReqLLM behaviour)

  @doc """
  Simulates a response for a given prompt.
  """
  @spec generate_text_mock(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_text_mock(%__MODULE__{simulate_timeout: true}, _prompt, _opts) do
    Process.sleep(100)
    {:error, :timeout}
  end

  def generate_text_mock(%__MODULE__{simulate_error: reason}, _prompt, _opts) when not is_nil(reason) do
    {:error, reason}
  end

  def generate_text_mock(%__MODULE__{}, prompt, _opts) do
    response = build_mock_response(prompt)
    {:ok, response}
  end

  # Private functions

  defp default_responses do
    [
      build_response("42", 10),
      build_response("The answer is 42", 15),
      build_response("345", 8)
    ]
  end

  defp build_response(content, tokens \\ 10) do
    # Build a minimal response map that matches what LLMGenerator.extract_content expects
    # The response should have a message field with content
    %{
      message: %{
        content: content
      },
      usage: %{
        input_tokens: div(tokens, 2),
        output_tokens: tokens - div(tokens, 2)
      }
    }
  end

  defp build_mock_response(prompt) do
    cond do
      String.contains?(prompt, "15 * 23") ->
        build_response("345", 12)

      String.contains?(prompt, "2+2") ->
        build_response("4", 8)

      String.contains?(prompt, "capital of Australia") ->
        build_response("Canberra", 15)

      String.contains?(prompt, "step by step") ->
        # Chain-of-Thought response
        content = """
        Let me think about this step by step.

        First, I need to understand the problem.
        Then, I'll work through it carefully.

        Final answer: The solution is 42.
        """

        build_response(content, 25)

      true ->
        # Default response
        build_response("I understand your question.", 10)
    end
  end
end
