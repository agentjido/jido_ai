defmodule Jido.AI.Helpers do
  @moduledoc """
  Helper utilities for common ReqLLM patterns in Jido.AI.

  This module provides utility functions for:
  - Message building and context management
  - Response processing and extraction
  - Error handling and classification

  ## Design Philosophy

  These helpers wrap and extend ReqLLM functionality for Jido.AI-specific patterns.
  For basic message construction, prefer using `ReqLLM.Context` directly:

      import ReqLLM.Context
      context = Context.new([
        system("You are helpful"),
        user("Hello")
      ])

  Use these helpers when you need Jido.AI-specific functionality like:
  - Error classification and conversion to Jido.AI.Error
  - Consistent response type classification
  - Integration with Jido.AI signals and directives

  ## Examples

      alias Jido.AI.Helpers

      # Build a context with system prompt
      {:ok, context} = Helpers.build_messages("Hello", system_prompt: "You are helpful")

      # Add a tool result to context
      context = Helpers.add_tool_result(context, "call_123", "calculator", %{result: 42})

      # Classify a response
      :final_answer = Helpers.classify_response(%{message: %{content: "Hello"}})

      # Convert ReqLLM error to Jido.AI.Error
      {:error, jido_error} = Helpers.wrap_error(reqllm_error)
  """

  alias Jido.AI.Config
  alias Jido.AI.Error
  alias Jido.AI.Error.API, as: APIError
  alias Jido.AI.Error.Validation, as: ValidationError
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  # ============================================================================
  # Message Building
  # ============================================================================

  @doc """
  Builds a ReqLLM.Context from a prompt with optional system message.

  This is a convenience wrapper around `ReqLLM.Context.normalize/2`.

  ## Arguments

    * `prompt` - String, Message, Context, or list of messages
    * `opts` - Options to pass to Context.normalize

  ## Options

    * `:system_prompt` - System message to add if none exists
    * `:validate` - Whether to validate the context (default: true)

  ## Returns

    * `{:ok, context}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> Helpers.build_messages("Hello")
      {:ok, %ReqLLM.Context{messages: [%ReqLLM.Message{role: :user, ...}]}}

      iex> Helpers.build_messages("Hello", system_prompt: "You are helpful")
      {:ok, %ReqLLM.Context{messages: [%ReqLLM.Message{role: :system, ...}, %ReqLLM.Message{role: :user, ...}]}}
  """
  @spec build_messages(term(), keyword()) :: {:ok, Context.t()} | {:error, term()}
  def build_messages(prompt, opts \\ []) do
    Context.normalize(prompt, opts)
  end

  @doc """
  Bang version of build_messages/2 that raises on error.
  """
  @spec build_messages!(term(), keyword()) :: Context.t()
  def build_messages!(prompt, opts \\ []) do
    Context.normalize!(prompt, opts)
  end

  @doc """
  Prepends a system message to a context if one doesn't exist.

  If the context already has a system message, returns the context unchanged.

  ## Arguments

    * `context` - A ReqLLM.Context struct
    * `system_prompt` - The system message text

  ## Returns

    Updated context with system message prepended.

  ## Examples

      iex> context = Context.new([Context.user("Hello")])
      iex> updated = Helpers.add_system_message(context, "You are helpful")
      iex> hd(updated.messages).role
      :system
  """
  @spec add_system_message(Context.t(), String.t()) :: Context.t()
  def add_system_message(%Context{messages: messages} = context, system_prompt) when is_binary(system_prompt) do
    has_system? = Enum.any?(messages, &(&1.role == :system))

    if has_system? do
      context
    else
      Context.prepend(context, Context.system(system_prompt))
    end
  end

  @doc """
  Adds a tool result message to the context.

  Creates a properly formatted tool result message and appends it to the context.
  The result is automatically JSON-encoded if it's not already a string.

  ## Arguments

    * `context` - A ReqLLM.Context struct
    * `tool_call_id` - The tool call ID from the LLM
    * `tool_name` - Name of the tool that was executed
    * `result` - The result to include (will be JSON-encoded if not a string)

  ## Returns

    Updated context with tool result message appended.

  ## Examples

      iex> context = Context.new([])
      iex> updated = Helpers.add_tool_result(context, "call_123", "calculator", %{result: 42})
      iex> hd(updated.messages).role
      :tool
  """
  @spec add_tool_result(Context.t(), String.t(), String.t(), term()) :: Context.t()
  def add_tool_result(%Context{} = context, tool_call_id, tool_name, result)
      when is_binary(tool_call_id) and is_binary(tool_name) do
    tool_result_msg = Context.tool_result_message(tool_name, tool_call_id, result)
    Context.append(context, tool_result_msg)
  end

  # ============================================================================
  # Response Processing
  # ============================================================================

  @doc """
  Extracts the text content from a ReqLLM response.

  Handles both string content and list of ContentPart structs.

  ## Arguments

    * `response` - A ReqLLM response map with `:message` key

  ## Returns

    The extracted text as a string, or empty string if no text content.

  ## Examples

      iex> Helpers.extract_text(%{message: %{content: "Hello"}})
      "Hello"

      iex> Helpers.extract_text(%{message: %{content: [%ContentPart{type: :text, text: "Hello"}]}})
      "Hello"
  """
  @spec extract_text(map()) :: String.t()
  def extract_text(%{message: %{content: content}}) when is_binary(content), do: content

  def extract_text(%{message: %{content: content}}) when is_list(content) do
    content
    |> Enum.filter(&match?(%{type: :text}, &1))
    |> Enum.map_join("", fn
      %ContentPart{text: text} -> text
      %{text: text} -> text
    end)
  end

  def extract_text(_), do: ""

  @doc """
  Extracts tool calls from a ReqLLM response.

  Returns a list of tool call maps with `:id`, `:name`, and `:arguments` keys.

  ## Arguments

    * `response` - A ReqLLM response map with `:message` key

  ## Returns

    List of tool call maps, or empty list if no tool calls.

  ## Examples

      iex> response = %{message: %{tool_calls: [%{id: "tc_1", name: "calc", arguments: %{}}]}}
      iex> Helpers.extract_tool_calls(response)
      [%{id: "tc_1", name: "calc", arguments: %{}}]

      iex> Helpers.extract_tool_calls(%{message: %{content: "Hello"}})
      []
  """
  @spec extract_tool_calls(map()) :: [map()]
  def extract_tool_calls(%{message: %{tool_calls: tool_calls}}) when is_list(tool_calls) do
    Enum.map(tool_calls, &normalize_tool_call_data/1)
  end

  def extract_tool_calls(_), do: []

  # Normalize a single tool call from various formats to a standard map
  defp normalize_tool_call_data(%ReqLLM.ToolCall{} = tool_call) do
    %{
      id: tool_call.id || generate_call_id(),
      name: ReqLLM.ToolCall.name(tool_call),
      arguments: ReqLLM.ToolCall.args_map(tool_call) || %{}
    }
  end

  defp normalize_tool_call_data(%{} = map) do
    %{
      id: map[:id] || map["id"] || generate_call_id(),
      name: map[:name] || map["name"],
      arguments: map[:arguments] || map["arguments"] || %{}
    }
  end

  defp generate_call_id, do: "call_#{:erlang.unique_integer([:positive])}"

  @doc """
  Checks if a ReqLLM response contains tool calls.

  ## Arguments

    * `response` - A ReqLLM response map with `:message` key

  ## Returns

    `true` if the response contains tool calls, `false` otherwise.

  ## Examples

      iex> Helpers.has_tool_calls?(%{message: %{tool_calls: [%{id: "tc_1"}]}})
      true

      iex> Helpers.has_tool_calls?(%{message: %{content: "Hello"}})
      false
  """
  @spec has_tool_calls?(map()) :: boolean()
  def has_tool_calls?(%{message: %{tool_calls: tool_calls}}) when is_list(tool_calls) and tool_calls != [], do: true

  def has_tool_calls?(_), do: false

  @doc """
  Classifies a ReqLLM response as tool calls, final answer, or error.

  ## Arguments

    * `response` - A ReqLLM response map or error tuple

  ## Returns

    * `:tool_calls` - Response contains tool calls to execute
    * `:final_answer` - Response is a text answer
    * `:error` - Response indicates an error

  ## Examples

      iex> Helpers.classify_response(%{message: %{tool_calls: [%{id: "tc_1"}]}})
      :tool_calls

      iex> Helpers.classify_response(%{message: %{content: "Hello"}})
      :final_answer

      iex> Helpers.classify_response({:error, %{reason: "timeout"}})
      :error
  """
  @spec classify_response(map() | {:error, term()}) :: :tool_calls | :final_answer | :error
  def classify_response({:error, _}), do: :error

  def classify_response(%{message: %{tool_calls: tool_calls}}) when is_list(tool_calls) and tool_calls != [],
    do: :tool_calls

  def classify_response(%{message: _}), do: :final_answer

  def classify_response(_), do: :error

  # ============================================================================
  # Error Handling
  # ============================================================================

  @doc """
  Classifies an error into a category for handling.

  ## Arguments

    * `error` - A ReqLLM error struct or error tuple

  ## Returns

    One of:
    * `:rate_limit` - Provider rate limit exceeded
    * `:auth` - Authentication/authorization error
    * `:timeout` - Request timeout
    * `:provider_error` - Provider-side error (5xx)
    * `:network` - Network connectivity error
    * `:validation` - Request validation error
    * `:unknown` - Unclassified error

  ## Examples

      iex> Helpers.classify_error(%ReqLLM.Error.API.Request{status: 429})
      :rate_limit

      iex> Helpers.classify_error(%ReqLLM.Error.API.Request{status: 401})
      :auth
  """
  @spec classify_error(term()) :: :rate_limit | :auth | :timeout | :provider_error | :network | :validation | :unknown
  def classify_error(%ReqLLM.Error.API.Request{status: 429}), do: :rate_limit
  def classify_error(%ReqLLM.Error.API.Request{status: 401}), do: :auth
  def classify_error(%ReqLLM.Error.API.Request{status: 403}), do: :auth

  def classify_error(%ReqLLM.Error.API.Request{status: status}) when is_integer(status) and status >= 500,
    do: :provider_error

  def classify_error(%ReqLLM.Error.API.Request{reason: reason}) when is_binary(reason) do
    reason_lower = String.downcase(reason)

    cond do
      String.contains?(reason_lower, "timeout") -> :timeout
      String.contains?(reason_lower, "rate") -> :rate_limit
      String.contains?(reason_lower, "econnrefused") -> :network
      String.contains?(reason_lower, "nxdomain") -> :network
      String.contains?(reason_lower, "connection") -> :network
      true -> :provider_error
    end
  end

  def classify_error(%ReqLLM.Error.Validation.Error{}), do: :validation
  def classify_error(%ReqLLM.Error.Invalid.Parameter{}), do: :validation
  def classify_error(%ReqLLM.Error.Invalid.Schema{}), do: :validation
  def classify_error(%ReqLLM.Error.Invalid.Message{}), do: :validation

  def classify_error({:error, :timeout}), do: :timeout
  def classify_error({:error, :econnrefused}), do: :network
  def classify_error({:error, :nxdomain}), do: :network

  def classify_error(_), do: :unknown

  @doc """
  Extracts retry-after seconds from a rate limit error.

  ## Arguments

    * `error` - A ReqLLM error struct

  ## Returns

    * Integer seconds to wait before retry
    * `nil` if no retry-after information available

  ## Examples

      iex> Helpers.extract_retry_after(%{response_body: %{"error" => %{"retry_after" => 60}}})
      60

      iex> Helpers.extract_retry_after(%{reason: "timeout"})
      nil
  """
  @spec extract_retry_after(term()) :: integer() | nil
  def extract_retry_after(%{response_body: %{"error" => %{"retry_after" => seconds}}}) when is_integer(seconds),
    do: seconds

  def extract_retry_after(%{response_body: %{"error" => %{"retry_after" => seconds}}}) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {n, _} -> n
      :error -> nil
    end
  end

  def extract_retry_after(%{response_body: %{"retry_after" => seconds}}) when is_integer(seconds), do: seconds

  def extract_retry_after(%{response_body: %{"retry_after" => seconds}}) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {n, _} -> n
      :error -> nil
    end
  end

  # Check for Retry-After header pattern in reason string
  def extract_retry_after(%{reason: reason}) when is_binary(reason) do
    case Regex.run(~r/retry.?after[:\s]+(\d+)/i, reason) do
      [_, seconds] ->
        case Integer.parse(seconds) do
          {n, _} -> n
          :error -> nil
        end

      nil ->
        nil
    end
  end

  def extract_retry_after(_), do: nil

  @doc """
  Wraps a ReqLLM error in a Jido.AI.Error with proper classification.

  Converts ReqLLM error types to appropriate Jido.AI.Error subtypes,
  preserving error details and adding classification metadata.

  ## Arguments

    * `error` - A ReqLLM error struct or error tuple

  ## Returns

    * `{:error, %Jido.AI.Error{}}` - Wrapped Jido.AI error

  ## Examples

      iex> reqllm_error = %ReqLLM.Error.API.Request{status: 429, reason: "Rate limited"}
      iex> {:error, jido_error} = Helpers.wrap_error(reqllm_error)
      iex> jido_error.__struct__
      Jido.AI.Error.API.RateLimit
  """
  @spec wrap_error(term()) :: {:error, struct()}
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

  # Extract a human-readable message from various error formats
  defp extract_error_message(%{reason: reason}) when is_binary(reason), do: reason
  defp extract_error_message(%{message: message}) when is_binary(message), do: message

  defp extract_error_message(%{response_body: %{"error" => %{"message" => message}}}) when is_binary(message),
    do: message

  defp extract_error_message({:error, reason}) when is_binary(reason), do: reason
  defp extract_error_message({:error, reason}) when is_atom(reason), do: to_string(reason)
  defp extract_error_message(error), do: inspect(error)

  # ============================================================================
  # Directive Helpers (shared across DirectiveExec implementations)
  # ============================================================================

  @doc """
  Resolves a model from directive fields.

  Supports both direct model specification and model alias resolution via Config.

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
      "anthropic:claude-haiku-4-5"  # resolved via Config
  """
  @spec resolve_directive_model(map()) :: String.t()
  def resolve_directive_model(%{model: model}) when is_binary(model) and model != "", do: model

  def resolve_directive_model(%{model_alias: alias_atom}) when is_atom(alias_atom) and not is_nil(alias_atom) do
    Config.resolve_model(alias_atom)
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

  ## Examples

      iex> Helpers.build_directive_messages([%{role: :user, content: "Hello"}], nil)
      [%{role: :user, content: "Hello"}]

      iex> Helpers.build_directive_messages([%{role: :user, content: "Hello"}], "Be helpful")
      [%{role: :system, content: "Be helpful"}, %{role: :user, content: "Hello"}]
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
  Normalizes a tool call from ReqLLM format to a standard map format.

  Handles both `ReqLLM.ToolCall` structs and plain maps with various key formats.

  ## Arguments

    * `tool_call` - A ReqLLM.ToolCall struct or map

  ## Returns

    A normalized map with `:id`, `:name`, and `:arguments` keys.

  ## Examples

      iex> Helpers.normalize_tool_call(%ReqLLM.ToolCall{id: "tc_1", ...})
      %{id: "tc_1", name: "calculator", arguments: %{a: 1}}
  """
  @spec normalize_tool_call(struct() | map()) :: map()
  def normalize_tool_call(%ReqLLM.ToolCall{} = tc) do
    %{
      id: tc.id || "call_#{:erlang.unique_integer([:positive])}",
      name: ReqLLM.ToolCall.name(tc),
      arguments: ReqLLM.ToolCall.args_map(tc) || %{}
    }
  end

  def normalize_tool_call(tool_call) when is_map(tool_call) do
    %{
      id: tool_call[:id] || tool_call["id"] || "call_#{:erlang.unique_integer([:positive])}",
      name: tool_call[:name] || tool_call["name"],
      arguments: parse_tool_arguments(tool_call[:arguments] || tool_call["arguments"] || %{})
    }
  end

  @doc """
  Parses tool call arguments, handling JSON strings.

  ## Arguments

    * `args` - Arguments as a map or JSON string

  ## Returns

    A map of parsed arguments.

  ## Examples

      iex> Helpers.parse_tool_arguments(%{a: 1})
      %{a: 1}

      iex> Helpers.parse_tool_arguments("{\"a\": 1}")
      %{"a" => 1}
  """
  @spec parse_tool_arguments(term()) :: map()
  def parse_tool_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} ->
        parsed

      {:error, _reason} ->
        require Logger

        Logger.warning("Failed to parse tool call arguments as JSON: #{inspect(args)}")
        %{}
    end
  end

  def parse_tool_arguments(args) when is_map(args), do: args
  def parse_tool_arguments(_), do: %{}

  @doc """
  Adds timeout option to a keyword list if timeout is specified.

  ## Arguments

    * `opts` - Keyword list of options
    * `timeout` - Timeout in milliseconds or nil

  ## Returns

    Updated keyword list with `:receive_timeout` added if timeout is not nil.
  """
  @spec add_timeout_opt(keyword(), integer() | nil) :: keyword()
  def add_timeout_opt(opts, nil), do: opts

  def add_timeout_opt(opts, timeout) when is_integer(timeout) do
    Keyword.put(opts, :receive_timeout, timeout)
  end

  @doc """
  Adds tools option to a keyword list if tools are specified.

  ## Arguments

    * `opts` - Keyword list of options
    * `tools` - List of tools or empty list

  ## Returns

    Updated keyword list with `:tools` added if tools list is not empty.
  """
  @spec add_tools_opt(keyword(), list()) :: keyword()
  def add_tools_opt(opts, []), do: opts
  def add_tools_opt(opts, tools), do: Keyword.put(opts, :tools, tools)

  @doc """
  Classifies a ReqLLM response into a result map.

  ## Arguments

    * `response` - A ReqLLM response struct

  ## Returns

    A map with `:type`, `:text`, and `:tool_calls` keys.

  ## Examples

      iex> Helpers.classify_llm_response(%{message: %{content: "Hello", tool_calls: []}})
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
      tool_calls: Enum.map(tool_calls, &normalize_tool_call/1)
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

  ## Examples

      # With instance state
      task_sup = Helpers.task_supervisor(state)
      Task.Supervisor.start_child(task_sup, fn -> ... end)

      # With explicit jido name
      task_sup = Helpers.task_supervisor(%{jido: MyApp.Jido})
  """
  @spec task_supervisor(map()) :: atom()
  def task_supervisor(%{jido: jido}) when not is_nil(jido) do
    Jido.task_supervisor_name(jido)
  end

  def task_supervisor(_state), do: Jido.TaskSupervisor
end
