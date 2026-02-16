defmodule Jido.AI.Actions.Helpers do
  @moduledoc """
  Shared helper functions for Jido.AI skill actions.

  This module provides common functionality used across multiple action modules
  to reduce code duplication and ensure consistent behavior.

  ## Functions

  * `resolve_model/2` - Resolve model alias to spec
  * `build_opts/2` - Build options for LLM requests
  * `extract_text/1` - Extract text from LLM response
  * `extract_usage/1` - Extract usage information from response
  * `validate_and_sanitize_input/2` - Validate input with security checks

  ## Examples

      use Jido.AI.Actions.Helpers

      # In an action
      def run(params, _context) do
        with {:ok, model} <- resolve_model(params[:model], :fast),
             {:ok, messages} <- build_messages(params),
             opts <- build_opts(params),
             {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, opts) do
          {:ok, format_result(response)}
        end
      end
  """

  alias Jido.AI.Security
  alias Jido.AI.Turn

  @doc """
  Resolves a model parameter to a model spec.

  ## Parameters

  * `model` - Model alias (atom) or direct spec (string)
  * `default` - Default model alias to use if model is nil

  ## Returns

  * `{:ok, model_spec}` - Successfully resolved model
  * `{:error, :invalid_model_format}` - Invalid model format

  ## Examples

      iex> resolve_model(nil, :fast)
      {:ok, "anthropic:claude-haiku-4-5"}

      iex> resolve_model(:capable, :fast)
      {:ok, "anthropic:claude-sonnet-4-20250514"}

      iex> resolve_model("openai:gpt-4", :fast)
      {:ok, "openai:gpt-4"}
  """
  def resolve_model(nil, default), do: {:ok, Jido.AI.resolve_model(default)}
  def resolve_model(model, _default) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  def resolve_model(model, _default) when is_binary(model), do: {:ok, model}
  def resolve_model(_model, _default), do: {:error, :invalid_model_format}

  @doc """
  Builds ReqLLM options from action parameters.

  ## Parameters

  * `params` - Map containing :max_tokens, :temperature, :timeout keys

  ## Returns

  Keyword list of options for ReqLLM

  ## Examples

      iex> build_opts(%{max_tokens: 1000, temperature: 0.5})
      [max_tokens: 1000, temperature: 0.5]

      iex> build_opts(%{max_tokens: 1000, temperature: 0.5, timeout: 5000})
      [max_tokens: 1000, temperature: 0.5, receive_timeout: 5000]
  """
  def build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  @doc """
  Extracts text content from an LLM response.

  Delegates to `Jido.AI.Turn.extract_text/1` which handles
  multiple response shapes consistently.

  ## Parameters

  * `response` - LLM response map

  ## Returns

  Extracted text string

  ## Examples

      iex> extract_text(%{message: %{content: "Hello"}})
      "Hello"

      iex> extract_text(%{message: %{content: [%{type: :text, text: "Hi"}]}})
      "Hi"
  """
  defdelegate extract_text(response), to: Turn

  @doc """
  Extracts usage information from an LLM response.

  ## Parameters

  * `response` - LLM response map

  ## Returns

  Map with :input_tokens, :output_tokens, :total_tokens keys

  ## Examples

      iex> extract_text(%{usage: %{input_tokens: 10, output_tokens: 20}})
      %{input_tokens: 10, output_tokens: 20, total_tokens: 30}
  """
  def extract_usage(%{usage: usage}) when is_map(usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0
    total_tokens = Map.get(usage, :total_tokens) || Map.get(usage, "total_tokens") || input_tokens + output_tokens

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  def extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  @doc """
  Validates and sanitizes input parameters with security checks.

  ## Parameters

  * `params` - Map of input parameters
  * `opts` - Validation options:
    * `:required_prompt` - Whether prompt is required (default: true)
    * `:required_system_prompt` - Whether system_prompt must be validated if present
    * `:max_prompt_length` - Max length for prompt (default: Security.max_input_length())
    * `:max_system_prompt_length` - Max length for system_prompt (default: Security.max_prompt_length())

  ## Returns

  * `{:ok, params}` - Validation passed
  * `{:error, reason}` - Validation failed

  ## Examples

      iex> validate_and_sanitize_input(%{prompt: "Hello"})
      {:ok, %{prompt: "Hello"}}

      iex> validate_and_sanitize_input(%{prompt: ""})
      {:error, :prompt_required}
  """
  def validate_and_sanitize_input(params, opts \\ []) do
    required_prompt = Keyword.get(opts, :required_prompt, true)
    max_prompt_length = Keyword.get(opts, :max_prompt_length, Security.max_input_length())
    max_system_prompt_length = Keyword.get(opts, :max_system_prompt_length, Security.max_prompt_length())

    with {:ok, _prompt} <- validate_prompt_if_required(params[:prompt], required_prompt, max_prompt_length),
         {:ok, _validated} <- validate_system_prompt_if_present(params, max_system_prompt_length) do
      {:ok, params}
    else
      {:error, :empty_string} when required_prompt -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_prompt_if_required(nil, true, _max_length), do: {:error, :empty_string}
  defp validate_prompt_if_required("", true, _max_length), do: {:error, :empty_string}

  defp validate_prompt_if_required(prompt, true, max_length) when is_binary(prompt) do
    Security.validate_string(prompt, max_length: max_length)
  end

  defp validate_prompt_if_required(_, false, _max_length), do: {:ok, nil}

  defp validate_system_prompt_if_present(%{system_prompt: system_prompt}, max_length) when is_binary(system_prompt) do
    Security.validate_string(system_prompt, max_length: max_length)
  end

  defp validate_system_prompt_if_present(_params, _max_length), do: {:ok, nil}

  @doc """
  Sanitizes an error for user-facing display.

  Uses Jido.AI.Security.sanitize_error_message/1 to convert
  detailed errors into generic user-safe messages.

  ## Parameters

  * `error` - The error term to sanitize

  ## Returns

  Sanitized error message string

  ## Examples

      iex> sanitize_error(%RuntimeError{message: "Internal error"})
      "An error occurred"

      iex> sanitize_error(:timeout)
      "Request timed out"
  """
  def sanitize_error(error) do
    Security.sanitize_error_message(error)
  end

  @doc """
  Formats a result with error sanitization.

  If the result is {:ok, _}, returns it as-is.
  If the result is {:error, _}, sanitizes the error message.

  ## Parameters

  * `result` - The result tuple to format

  ## Returns

  Formatted result tuple

  ## Examples

      iex> format_result({:ok, %{text: "Hello"}})
      {:ok, %{text: "Hello"}}

      iex> format_result({:error, %RuntimeError{message: "Internal"}})
      {:error, "An error occurred"}
  """
  def format_result({:ok, _value} = ok_result), do: ok_result

  def format_result({:error, error}) do
    {:error, sanitize_error(error)}
  end
end
