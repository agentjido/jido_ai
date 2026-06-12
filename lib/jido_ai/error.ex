defmodule Jido.AI.Error do
  @moduledoc """
  Splode-based error handling for Jido.AI.

  Provides structured error types for AI operations including:
  - API errors (rate limits, authentication, transient failures)
  - Validation errors
  - Runtime error envelope normalization and retryability policy
  """

  use Splode,
    error_classes: [
      api: Jido.AI.Error.API,
      validation: Jido.AI.Error.Validation
    ],
    unknown_error: Jido.AI.Error.Unknown

  @upstream_jido_error_prefixes [
    "Elixir.Jido.Action.Error.",
    "Elixir.Jido.Error.",
    "Elixir.Jido.Signal.Error."
  ]

  @type error_envelope :: %{
          type: atom(),
          message: String.t(),
          details: map(),
          retryable?: boolean()
        }

  @doc """
  Builds a normalized AI runtime error envelope.

  The envelope is the package-owned caller-visible contract used by tool,
  LLM, directive, and signal result paths.
  """
  @spec error_envelope(atom(), String.t(), map(), boolean()) :: error_envelope()
  def error_envelope(type, message, details \\ %{}, retryable? \\ false)
      when is_atom(type) and is_binary(message) and is_map(details) and is_boolean(retryable?) do
    %{
      type: type,
      message: message,
      details: normalize_json_safe_map(details),
      retryable?: retryable?
    }
  end

  @doc """
  Normalizes arbitrary runtime error values into the canonical AI error envelope.
  """
  @spec normalize(term(), atom(), String.t(), map()) :: error_envelope()
  def normalize(reason, fallback_type \\ :execution_error, fallback_message \\ "Execution failed", extra_details \\ %{})

  def normalize(%{type: type, message: message} = error, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_map(extra_details) do
    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%{type: type, message: message} = error, fallback_type, _fallback_message, extra_details)
      when is_binary(type) and is_map(extra_details) do
    type = normalize_type(type, fallback_type)

    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%{code: type, message: message} = error, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_map(extra_details) do
    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%{code: type, message: message} = error, fallback_type, _fallback_message, extra_details)
      when is_binary(type) and is_map(extra_details) do
    type = normalize_type(type, fallback_type)

    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%{"type" => type, "message" => message} = error, fallback_type, _fallback_message, extra_details)
      when is_binary(type) and is_map(extra_details) do
    type = normalize_type(type, fallback_type)

    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%{"code" => type, "message" => message} = error, fallback_type, _fallback_message, extra_details)
      when is_binary(type) and is_map(extra_details) do
    type = normalize_type(type, fallback_type)

    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(error_details(error), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize(%module{} = reason, fallback_type, fallback_message, extra_details)
      when is_map(extra_details) do
    cond do
      upstream_jido_error_struct?(module) ->
        normalize_upstream_jido_error(reason, fallback_type, fallback_message, extra_details)

      is_exception(reason) ->
        normalize_exception(reason, fallback_type, extra_details)

      true ->
        error_envelope(
          fallback_type,
          fallback_message,
          merge_error_details(%{reason: inspect(reason)}, extra_details),
          false
        )
    end
  end

  def normalize(%{message: message} = error, fallback_type, _fallback_message, extra_details)
      when not is_nil(message) and is_map(extra_details) do
    details =
      error
      |> Map.drop([:message, :retryable, :retryable?, "message", "retryable", "retryable?"])
      |> merge_error_details(extra_details)

    error_envelope(fallback_type, normalize_message(message), details, normalize_retryable(error, fallback_type))
  end

  def normalize({:error, reason}, fallback_type, fallback_message, extra_details)
      when is_map(extra_details) do
    normalize(reason, fallback_type, fallback_message, extra_details)
  end

  def normalize({:unknown_tool, message}, _fallback_type, _fallback_message, extra_details)
      when is_binary(message) and is_map(extra_details) do
    error_envelope(:unknown_tool, message, extra_details, false)
  end

  def normalize({type, message}, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_binary(message) and is_map(extra_details) do
    error_envelope(type, message, extra_details, retryable_type?(type))
  end

  def normalize({:validation, details}, _fallback_type, _fallback_message, extra_details)
      when is_map(extra_details) do
    error_envelope(
      :validation,
      "Tool validation failed",
      merge_error_details(%{details: details}, extra_details),
      false
    )
  end

  def normalize({:timeout, details}, _fallback_type, _fallback_message, extra_details)
      when is_map(details) and is_map(extra_details) do
    error_envelope(:timeout, "Tool execution timed out", merge_error_details(details, extra_details), true)
  end

  def normalize(:timeout, _fallback_type, _fallback_message, extra_details) when is_map(extra_details) do
    error_envelope(:timeout, "Tool execution timed out", extra_details, true)
  end

  def normalize(reason, fallback_type, _fallback_message, extra_details)
      when is_atom(reason) and is_map(extra_details) do
    error_envelope(
      fallback_type,
      Atom.to_string(reason),
      merge_error_details(%{reason: reason}, extra_details),
      retryable_type?(reason)
    )
  end

  def normalize(reason, fallback_type, fallback_message, extra_details) when is_map(extra_details) do
    error_envelope(
      fallback_type,
      fallback_message,
      merge_error_details(%{reason: inspect(reason)}, extra_details),
      retryable_type?(fallback_type)
    )
  end

  @doc """
  Serializes a runtime error term as the canonical AI runtime error map.
  """
  @spec to_map(term()) :: error_envelope()
  def to_map(reason), do: normalize(reason)

  @doc """
  Ensures result payloads use `{:ok, term, effects}` or `{:error, reason, effects}` tuples.
  """
  @spec normalize_result(term(), atom(), String.t()) ::
          {:ok, term(), [term()]} | {:error, error_envelope(), [term()]}
  def normalize_result(result, fallback_type \\ :invalid_result, fallback_message \\ "Invalid result envelope")

  def normalize_result({:ok, value, effects}, _fallback_type, _fallback_message),
    do: {:ok, value, List.wrap(effects)}

  def normalize_result({:ok, value}, _fallback_type, _fallback_message), do: {:ok, value, []}

  def normalize_result({:error, reason, effects}, fallback_type, fallback_message),
    do: {:error, normalize(reason, fallback_type, fallback_message), List.wrap(effects)}

  def normalize_result({:error, reason}, fallback_type, fallback_message),
    do: {:error, normalize(reason, fallback_type, fallback_message), []}

  def normalize_result(result, fallback_type, fallback_message) do
    {:error, error_envelope(fallback_type, fallback_message, %{result: inspect(result)}), []}
  end

  @doc """
  Returns whether a result or error should be treated as retryable by runtime policy.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?({:ok, _, _}), do: false
  def retryable?({:ok, _}), do: false
  def retryable?({:error, reason, _effects}), do: retryable?(reason)
  def retryable?({:error, reason}), do: retryable?(reason)
  def retryable?(%{retryable?: value}) when is_boolean(value), do: value
  def retryable?(%{retryable: value}) when is_boolean(value), do: value
  def retryable?(%{"retryable?" => value}) when is_boolean(value), do: value
  def retryable?(%{"retryable" => value}) when is_boolean(value), do: value
  def retryable?(%{type: type} = error) when is_atom(type), do: retryable_hint(error, retryable_type?(type))
  def retryable?(%{code: type} = error) when is_atom(type), do: retryable_hint(error, retryable_type?(type))
  def retryable?(%{type: type} = error) when is_binary(type), do: retryable_from_string_type(error, type)
  def retryable?(%{code: type} = error) when is_binary(type), do: retryable_from_string_type(error, type)
  def retryable?(%{"type" => type} = error) when is_binary(type), do: retryable_from_string_type(error, type)
  def retryable?(%{"code" => type} = error) when is_binary(type), do: retryable_from_string_type(error, type)
  def retryable?(reason) when is_atom(reason), do: retryable_type?(reason)
  def retryable?(_reason), do: false

  defp merge_error_details(details, extra_details) when is_map(details) and is_map(extra_details) do
    Map.merge(details, extra_details)
    |> normalize_json_safe_map()
  end

  defp merge_error_details(details, extra_details) when is_map(extra_details) do
    details
    |> normalize_error_details()
    |> Map.merge(extra_details)
    |> normalize_json_safe_map()
  end

  defp normalize_error_details(nil), do: %{}
  defp normalize_error_details(details), do: %{details: details}

  defp normalize_json_safe_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {normalize_json_safe_key(key), normalize_json_safe_value(value)}
    end)
  end

  defp normalize_json_safe_key(key) when is_binary(key), do: key
  defp normalize_json_safe_key(key) when is_atom(key), do: key
  defp normalize_json_safe_key(key), do: inspect(key)

  defp normalize_json_safe_value(value) when is_nil(value), do: nil
  defp normalize_json_safe_value(value) when is_boolean(value), do: value
  defp normalize_json_safe_value(value) when is_integer(value), do: value
  defp normalize_json_safe_value(value) when is_float(value), do: value
  defp normalize_json_safe_value(value) when is_binary(value), do: value
  defp normalize_json_safe_value(value) when is_atom(value), do: value

  defp normalize_json_safe_value(value) when is_list(value) do
    if proper_list?(value) do
      Enum.map(value, &normalize_json_safe_value/1)
    else
      inspect(value)
    end
  end

  defp normalize_json_safe_value(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_json_safe_map()
  end

  defp normalize_json_safe_value(value) when is_map(value) do
    normalize_json_safe_map(value)
  end

  defp normalize_json_safe_value(value), do: inspect(value)

  defp normalize_retryable(error, type) do
    cond do
      is_boolean(Map.get(error, :retryable?)) -> Map.get(error, :retryable?)
      is_boolean(Map.get(error, "retryable?")) -> Map.get(error, "retryable?")
      is_boolean(Map.get(error, :retryable)) -> Map.get(error, :retryable)
      is_boolean(Map.get(error, "retryable")) -> Map.get(error, "retryable")
      true -> retryable_hint(error, retryable_type?(type))
    end
  end

  defp error_details(error), do: Map.get(error, :details, Map.get(error, "details", %{}))

  defp normalize_type(type, fallback) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> fallback
  end

  defp normalize_message(message) when is_binary(message), do: message
  defp normalize_message(nil), do: "Execution failed"
  defp normalize_message(message) when is_atom(message), do: Atom.to_string(message)
  defp normalize_message(message), do: inspect(message)

  defp normalize_upstream_jido_error(reason, fallback_type, fallback_message, extra_details) do
    reason
    |> Jido.Error.to_map()
    |> Map.drop([:stacktrace])
    |> normalize(fallback_type, fallback_message, extra_details)
  end

  defp normalize_exception(reason, fallback_type, extra_details) do
    error_envelope(
      fallback_type,
      Exception.message(reason),
      merge_error_details(Map.from_struct(reason), extra_details),
      false
    )
  end

  defp upstream_jido_error_struct?(module) do
    jido_error_adapter_available?() and exception_struct?(module) and jido_error_namespace?(module)
  end

  defp jido_error_adapter_available? do
    Code.ensure_loaded?(Jido.Error) and function_exported?(Jido.Error, :to_map, 1)
  end

  defp exception_struct?(module), do: function_exported?(module, :message, 1)

  defp jido_error_namespace?(module) do
    module_name = Atom.to_string(module)

    String.starts_with?(module_name, @upstream_jido_error_prefixes)
  end

  defp retryable_from_string_type(error, type) do
    case normalize_type(type, nil) do
      nil -> retryable_hint(error, false)
      type -> retryable_hint(error, retryable_type?(type))
    end
  end

  defp retryable_hint(term, default) do
    case extract_retry_hint(term) do
      nil -> default
      value -> retry_hint_truthy?(value)
    end
  end

  defp retry_hint_truthy?(false), do: false
  defp retry_hint_truthy?(0), do: false

  defp retry_hint_truthy?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 not in ["", "0", "false", "no", "off"]))
  end

  defp retry_hint_truthy?(_), do: true

  defp extract_retry_hint(%{details: details} = error) do
    case extract_retry_value(details) do
      nil ->
        details
        |> extract_nested_reason()
        |> Kernel.||(extract_nested_reason(error))
        |> extract_retry_hint()

      value ->
        value
    end
  end

  defp extract_retry_hint(%{"details" => details} = error) do
    case extract_retry_value(details) do
      nil ->
        details
        |> extract_nested_reason()
        |> Kernel.||(extract_nested_reason(error))
        |> extract_retry_hint()

      value ->
        value
    end
  end

  defp extract_retry_hint(%{} = map) do
    case extract_retry_value(map) do
      nil -> map |> extract_nested_reason() |> extract_retry_hint()
      value -> value
    end
  end

  defp extract_retry_hint(nil), do: nil
  defp extract_retry_hint(reason) when is_atom(reason), do: retryable_type?(reason)
  defp extract_retry_hint(reason) when is_binary(reason), do: retryable_type_from_string(reason)
  defp extract_retry_hint(_), do: nil

  defp extract_nested_reason(%{} = map) do
    map[:reason] ||
      map["reason"] ||
      retry_hint_message(map[:message]) ||
      retry_hint_message(map["message"])
  end

  defp extract_nested_reason(_), do: nil

  defp extract_retry_value(%{} = map) do
    cond do
      Map.has_key?(map, :retry) -> map[:retry]
      Map.has_key?(map, "retry") -> map["retry"]
      Map.has_key?(map, :retryable?) -> map[:retryable?]
      Map.has_key?(map, "retryable?") -> map["retryable?"]
      Map.has_key?(map, :retryable) -> map[:retryable]
      Map.has_key?(map, "retryable") -> map["retryable"]
      true -> nil
    end
  end

  defp extract_retry_value(keyword) when is_list(keyword) do
    if Keyword.keyword?(keyword), do: Keyword.get(keyword, :retry), else: nil
  end

  defp extract_retry_value(_), do: nil

  defp retry_hint_message(message) when is_atom(message), do: message
  defp retry_hint_message(message) when is_binary(message), do: normalize_type(message, nil)
  defp retry_hint_message(_), do: nil

  defp retryable_type_from_string(type) do
    case normalize_type(type, nil) do
      nil -> nil
      type -> retryable_type?(type)
    end
  end

  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_), do: false

  defp retryable_type?(type) when type in [:timeout, :transient, :transient_error, :rate_limited], do: true
  defp retryable_type?(_type), do: false
end

defmodule Jido.AI.Error.API do
  @moduledoc "API-level errors from LLM providers"

  use Splode.ErrorClass,
    class: :api
end

defmodule Jido.AI.Error.Validation do
  @moduledoc "Input/output validation errors"

  use Splode.ErrorClass,
    class: :validation
end

defmodule Jido.AI.Error.Unknown do
  @moduledoc "Fallback error for unknown error types"

  use Splode.Error,
    fields: [:error],
    class: :unknown

  @impl true
  def message(%{error: error}) do
    "Unknown error: #{inspect(error)}"
  end
end

# ============================================================================
# API Error Types
# ============================================================================

defmodule Jido.AI.Error.API.RateLimit do
  @moduledoc "Rate limit exceeded error"

  use Splode.Error,
    fields: [:message, :retry_after],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{retry_after: seconds}) when is_integer(seconds),
    do: "Rate limit exceeded, retry after #{seconds} seconds"

  def message(_), do: "Rate limit exceeded"
end

defmodule Jido.AI.Error.API.Auth do
  @moduledoc "Authentication/authorization error"

  use Splode.Error,
    fields: [:message],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "Authentication failed"
end

defmodule Jido.AI.Error.API.Request do
  @moduledoc """
  Transient request failure error.

  Covers timeout, network, and provider errors - all transient failures
  that may be retried.
  """

  use Splode.Error,
    fields: [:message, :kind, :status],
    class: :api

  @type kind :: :timeout | :network | :provider

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{kind: :timeout}), do: "Request timed out"
  def message(%{kind: :network}), do: "Network error"
  def message(%{kind: :provider, status: status}) when is_integer(status), do: "Provider error (#{status})"
  def message(%{kind: :provider}), do: "Provider error"
  def message(_), do: "Request failed"
end

# ============================================================================
# Validation Error Types
# ============================================================================

defmodule Jido.AI.Error.Validation.Invalid do
  @moduledoc "Input validation error"

  use Splode.Error,
    fields: [:message, :field],
    class: :validation

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{field: field}) when is_binary(field), do: "Invalid field: #{field}"
  def message(_), do: "Validation error"
end

defmodule Jido.AI.Error.Validation.Output do
  @moduledoc "Structured output validation error"

  use Splode.Error,
    fields: [:message, :field, :details],
    class: :validation

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{field: field}) when field in [:output, "output"], do: "Structured output validation failed"
  def message(_), do: "Structured output validation failed"
end
