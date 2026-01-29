defmodule Jido.AI.Helpers do
  @moduledoc """
  Jido.AI-specific helper utilities.

  This module provides utilities for:
  - Error handling and classification (mapping ReqLLM errors → Jido.AI.Error)
  - Response classification for LLM responses
  - Directive execution support

  For message building and context management, use `ReqLLM.Context` directly:

      alias ReqLLM.Context

      {:ok, context} = Context.normalize("Hello", system_prompt: "You are helpful")
      context = Context.append(context, Context.user("Follow up"))

  ## Examples

      alias Jido.AI.Helpers

      # Classify an LLM response
      result = Helpers.classify_llm_response(response)
      # => %{type: :final_answer, text: "Hello", tool_calls: []}

      # Convert ReqLLM error to Jido.AI.Error
      {:error, jido_error} = Helpers.wrap_error(reqllm_error)

      # Classify error type
      :rate_limit = Helpers.classify_error(rate_limit_error)
  """

  alias Jido.AI.Error
  alias Jido.AI.Error.API, as: APIError
  alias Jido.AI.Error.Validation, as: ValidationError
  alias Jido.AI.ToolCall

  # ============================================================================
  # Error Handling
  # ============================================================================

  @doc """
  Classifies an error into a category for Jido.AI.Error conversion.

  Returns one of: `:rate_limit`, `:auth`, `:timeout`, `:provider_error`,
  `:network`, `:validation`, `:unknown`

  ## Arguments

    * `error` - Any error value (exception, tuple, map, etc.)

  ## Examples

      iex> Helpers.classify_error(%{status: 429})
      :rate_limit

      iex> Helpers.classify_error(%{status: 401})
      :auth

      iex> Helpers.classify_error(:timeout)
      :timeout
  """
  @spec classify_error(term()) :: atom()
  def classify_error(%{status: status}) when status == 429, do: :rate_limit
  def classify_error(%{status: status}) when status in [401, 403], do: :auth
  def classify_error(%{status: status}) when status >= 500, do: :provider_error
  def classify_error(%{status: status}) when status >= 400, do: :validation

  def classify_error(%{reason: :timeout}), do: :timeout
  def classify_error(%{reason: :connect_timeout}), do: :timeout
  def classify_error(%{reason: :checkout_timeout}), do: :timeout

  def classify_error(%{reason: reason}) when reason in [:econnrefused, :nxdomain, :closed], do: :network

  def classify_error({:error, :timeout}), do: :timeout
  def classify_error(:timeout), do: :timeout

  def classify_error(%Mint.TransportError{}), do: :network
  def classify_error(%Mint.HTTPError{}), do: :network

  def classify_error(_), do: :unknown

  @doc """
  Extracts retry_after value from rate limit errors.

  ## Arguments

    * `error` - An error that may contain retry_after information

  ## Returns

    The retry_after value in seconds, or nil if not present.
  """
  @spec extract_retry_after(term()) :: integer() | nil
  def extract_retry_after(%{response_headers: headers}) when is_list(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> parse_retry_after(value)
      nil -> nil
    end
  end

  def extract_retry_after(%{retry_after: value}) when is_integer(value), do: value
  def extract_retry_after(_), do: nil

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_retry_after(value) when is_integer(value), do: value
  defp parse_retry_after(_), do: nil

  @doc """
  Wraps a ReqLLM error into a Jido.AI.Error struct.

  Converts various error formats from ReqLLM into the appropriate
  Jido.AI.Error type using Splode.

  ## Arguments

    * `error` - The error to wrap

  ## Returns

    `{:error, Jido.AI.Error}` with the appropriate error type.
  """
  @spec wrap_error(term()) :: {:error, Exception.t()}
  def wrap_error(error) do
    error_type = classify_error(error)
    message = extract_error_message(error)
    retry_after = extract_retry_after(error)

    jido_error =
      case error_type do
        :rate_limit ->
          APIError.RateLimit.exception(message: message, retry_after: retry_after)

        :auth ->
          APIError.Auth.exception(message: message)

        :timeout ->
          APIError.Timeout.exception(message: message)

        :provider_error ->
          APIError.Provider.exception(message: message)

        :network ->
          APIError.Network.exception(message: message)

        :validation ->
          ValidationError.Invalid.exception(message: message)

        :unknown ->
          Error.Unknown.exception(error: error)
      end

    {:error, jido_error}
  end

  defp extract_error_message(%{reason: reason}) when is_binary(reason), do: reason
  defp extract_error_message(%{message: message}) when is_binary(message), do: message

  defp extract_error_message(%{response_body: %{"error" => %{"message" => message}}}) when is_binary(message),
    do: message

  defp extract_error_message({:error, reason}) when is_binary(reason), do: reason
  defp extract_error_message({:error, reason}) when is_atom(reason), do: to_string(reason)
  defp extract_error_message(error), do: inspect(error)

  # ============================================================================
  # Directive Helpers
  # ============================================================================

  @doc """
  Resolves a model from directive fields.

  Supports both direct model specification and model alias resolution.

  ## Arguments

    * `directive` - A directive struct with `:model` and/or `:model_alias` fields

  ## Returns

    The resolved model spec string.

  ## Raises

    `ArgumentError` if neither `:model` nor `:model_alias` is provided.

  ## Examples

      iex> Helpers.resolve_directive_model(%{model: "anthropic:claude-haiku-4-5"})
      "anthropic:claude-haiku-4-5"

      iex> Helpers.resolve_directive_model(%{model_alias: :fast})
      "anthropic:claude-haiku-4-5"
  """
  @spec resolve_directive_model(map()) :: String.t()
  def resolve_directive_model(%{model: model}) when is_binary(model) and model != "", do: model

  def resolve_directive_model(%{model_alias: alias_atom}) when is_atom(alias_atom) and not is_nil(alias_atom) do
    Jido.AI.resolve_model(alias_atom)
  end

  def resolve_directive_model(%{model: nil, model_alias: nil}) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  def resolve_directive_model(_) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  @doc """
  Builds messages for LLM calls from context and optional system prompt.

  ## Arguments

    * `context` - A ReqLLM.Context, list of messages, or map with `:messages` key
    * `system_prompt` - Optional system prompt to prepend

  ## Returns

    A list of messages ready for ReqLLM.
  """
  @spec build_directive_messages(term(), String.t() | nil) :: list()
  def build_directive_messages(context, nil), do: normalize_directive_messages(context)

  def build_directive_messages(context, system_prompt) when is_binary(system_prompt) do
    messages = normalize_directive_messages(context)
    system_message = %{role: :system, content: system_prompt}
    [system_message | messages]
  end

  @doc false
  @spec normalize_directive_messages(term()) :: list()
  def normalize_directive_messages(%{messages: msgs}), do: msgs
  def normalize_directive_messages(msgs) when is_list(msgs), do: msgs
  def normalize_directive_messages(context), do: context

  @doc """
  Adds timeout option to a keyword list if timeout is specified.
  """
  @spec add_timeout_opt(keyword(), integer() | nil) :: keyword()
  def add_timeout_opt(opts, nil), do: opts

  def add_timeout_opt(opts, timeout) when is_integer(timeout) do
    Keyword.put(opts, :receive_timeout, timeout)
  end

  @doc """
  Adds tools option to a keyword list if tools are specified.
  """
  @spec add_tools_opt(keyword(), list()) :: keyword()
  def add_tools_opt(opts, []), do: opts
  def add_tools_opt(opts, tools), do: Keyword.put(opts, :tools, tools)

  # ============================================================================
  # Response Classification
  # ============================================================================

  @doc """
  Classifies a ReqLLM response into a result map.

  ## Arguments

    * `response` - A ReqLLM response struct

  ## Returns

    A map with `:type`, `:text`, and `:tool_calls` keys.

  ## Examples

      iex> Helpers.classify_llm_response(%{message: %{content: "Hello", tool_calls: []}, finish_reason: :stop})
      %{type: :final_answer, text: "Hello", tool_calls: []}
  """
  @spec classify_llm_response(map()) :: map()
  def classify_llm_response(response) do
    tool_calls = response.message.tool_calls || []

    type =
      cond do
        tool_calls != [] -> :tool_calls
        response.finish_reason == :tool_calls -> :tool_calls
        true -> :final_answer
      end

    %{
      type: type,
      text: extract_response_text(response.message.content),
      tool_calls: Enum.map(tool_calls, &ToolCall.normalize/1)
    }
  end

  @doc false
  @spec extract_response_text(term()) :: String.t()
  def extract_response_text(nil), do: ""
  def extract_response_text(content) when is_binary(content), do: content

  def extract_response_text(content) when is_list(content) do
    content
    |> Enum.filter(&match?(%{type: :text}, &1))
    |> Enum.map_join("", & &1.text)
  end

  # ============================================================================
  # Task Supervisor Helpers
  # ============================================================================

  @doc """
  Returns the task supervisor name for the given Jido instance.

  Uses instance-specific task supervisor from state.jido if available,
  otherwise falls back to global Jido.TaskSupervisor for backwards compatibility.
  """
  @spec task_supervisor(map()) :: atom()
  def task_supervisor(%{jido: jido}) when not is_nil(jido) do
    Jido.task_supervisor_name(jido)
  end

  def task_supervisor(_state), do: Jido.TaskSupervisor
end
