defmodule Jido.AI.Signal.Helpers do
  @moduledoc """
  Shared helpers for signal correlation and standardized error envelopes.
  """

  alias Jido.Signal

  @type error_envelope :: %{
          type: atom(),
          message: String.t(),
          details: map(),
          retryable?: boolean()
        }

  @doc """
  Builds a normalized error envelope for signal payloads.
  """
  @spec error_envelope(atom(), String.t(), map(), boolean()) :: error_envelope()
  def error_envelope(type, message, details \\ %{}, retryable? \\ false)
      when is_atom(type) and is_binary(message) and is_map(details) and is_boolean(retryable?) do
    %{
      type: type,
      message: message,
      details: details,
      retryable?: retryable?
    }
  end

  @doc """
  Normalizes arbitrary error values into the canonical AI error envelope.
  """
  @spec normalize_error(term(), atom(), String.t(), map()) :: error_envelope()
  def normalize_error(
        reason,
        fallback_type \\ :execution_error,
        fallback_message \\ "Execution failed",
        extra_details \\ %{}
      )

  def normalize_error(%{type: type, message: message} = error, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_map(extra_details) do
    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(Map.get(error, :details, %{}), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize_error(%{code: type, message: message} = error, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_map(extra_details) do
    error_envelope(
      type,
      normalize_message(message),
      merge_error_details(Map.get(error, :details, %{}), extra_details),
      normalize_retryable(error, type)
    )
  end

  def normalize_error(%{message: message} = error, fallback_type, _fallback_message, extra_details)
      when not is_nil(message) and is_map(extra_details) do
    details =
      error
      |> Map.drop([:message, :retryable, :retryable?])
      |> merge_error_details(extra_details)

    error_envelope(fallback_type, normalize_message(message), details, normalize_retryable(error, fallback_type))
  end

  def normalize_error(%module{} = reason, fallback_type, fallback_message, extra_details)
      when is_map(extra_details) do
    cond do
      function_exported?(Jido.Error, :to_map, 1) and function_exported?(module, :message, 1) ->
        reason
        |> Jido.Error.to_map()
        |> Map.drop([:stacktrace])
        |> normalize_error(fallback_type, fallback_message, extra_details)

      is_exception(reason) ->
        error_envelope(
          fallback_type,
          Exception.message(reason),
          merge_error_details(Map.from_struct(reason), extra_details),
          false
        )

      true ->
        error_envelope(
          fallback_type,
          fallback_message,
          merge_error_details(%{reason: inspect(reason)}, extra_details),
          false
        )
    end
  end

  def normalize_error({type, message}, _fallback_type, _fallback_message, extra_details)
      when is_atom(type) and is_binary(message) and is_map(extra_details) do
    error_envelope(type, message, extra_details, retryable_type?(type))
  end

  def normalize_error({:error, reason}, fallback_type, fallback_message, extra_details)
      when is_map(extra_details) do
    normalize_error(reason, fallback_type, fallback_message, extra_details)
  end

  def normalize_error({:unknown_tool, message}, _fallback_type, _fallback_message, extra_details)
      when is_binary(message) and is_map(extra_details) do
    error_envelope(:unknown_tool, message, extra_details, false)
  end

  def normalize_error({:validation, details}, _fallback_type, _fallback_message, extra_details)
      when is_map(extra_details) do
    error_envelope(
      :validation,
      "Tool validation failed",
      merge_error_details(%{details: details}, extra_details),
      false
    )
  end

  def normalize_error({:timeout, details}, _fallback_type, _fallback_message, extra_details)
      when is_map(details) and is_map(extra_details) do
    error_envelope(:timeout, "Tool execution timed out", merge_error_details(details, extra_details), true)
  end

  def normalize_error(:timeout, _fallback_type, _fallback_message, extra_details) when is_map(extra_details) do
    error_envelope(:timeout, "Tool execution timed out", extra_details, true)
  end

  def normalize_error(reason, fallback_type, _fallback_message, extra_details)
      when is_atom(reason) and is_map(extra_details) do
    error_envelope(
      fallback_type,
      Atom.to_string(reason),
      merge_error_details(%{reason: reason}, extra_details),
      retryable_type?(reason)
    )
  end

  def normalize_error(reason, fallback_type, fallback_message, extra_details) when is_map(extra_details) do
    error_envelope(
      fallback_type,
      fallback_message,
      merge_error_details(%{reason: inspect(reason)}, extra_details),
      retryable_type?(fallback_type)
    )
  end

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
    do: {:error, normalize_error(reason, fallback_type, fallback_message), List.wrap(effects)}

  def normalize_result({:error, reason}, fallback_type, fallback_message),
    do: {:error, normalize_error(reason, fallback_type, fallback_message), []}

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
  def retryable?(%{type: type} = error) when is_atom(type), do: retryable_hint(error, retryable_type?(type))
  def retryable?(%{code: type} = error) when is_atom(type), do: retryable_hint(error, retryable_type?(type))
  def retryable?(reason) when is_atom(reason), do: retryable_type?(reason)
  def retryable?(_reason), do: false

  @doc """
  Extracts the best available request/call correlation identifier from signal data.
  """
  @spec correlation_id(Signal.t() | map() | nil) :: String.t() | nil
  def correlation_id(%Signal{data: data}), do: correlation_id(data)

  def correlation_id(%{} = data) do
    first_present([
      Map.get(data, :request_id),
      Map.get(data, "request_id"),
      Map.get(data, :call_id),
      Map.get(data, "call_id"),
      Map.get(data, :run_id),
      Map.get(data, "run_id"),
      Map.get(data, :id),
      Map.get(data, "id")
    ])
  end

  def correlation_id(_), do: nil

  @doc """
  Sanitizes streaming deltas by removing control bytes and truncating payload size.
  """
  @spec sanitize_delta(term(), non_neg_integer()) :: String.t()
  def sanitize_delta(delta, max_chars \\ 4_000) when is_integer(max_chars) and max_chars > 0 do
    delta
    |> to_string()
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
    |> String.slice(0, max_chars)
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))

  defp merge_error_details(details, extra_details) when is_map(details) and is_map(extra_details) do
    Map.merge(details, extra_details)
  end

  defp normalize_retryable(error, type) do
    cond do
      is_boolean(Map.get(error, :retryable?)) -> Map.get(error, :retryable?)
      is_boolean(Map.get(error, :retryable)) -> Map.get(error, :retryable)
      true -> retryable_hint(error, retryable_type?(type))
    end
  end

  defp normalize_message(message) when is_binary(message), do: message
  defp normalize_message(message) when is_atom(message), do: Atom.to_string(message)
  defp normalize_message(nil), do: "Execution failed"
  defp normalize_message(message), do: inspect(message)

  defp retryable_hint(term, default) do
    case extract_retry_hint(term) do
      nil -> default
      value -> value != false
    end
  end

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

  defp extract_retry_hint(%{} = map) do
    case extract_retry_value(map) do
      nil -> map |> extract_nested_reason() |> extract_retry_hint()
      value -> value
    end
  end

  defp extract_retry_hint(nil), do: nil
  defp extract_retry_hint(reason) when is_atom(reason), do: retryable_type?(reason)
  defp extract_retry_hint(_), do: nil

  defp extract_nested_reason(%{} = map) do
    Map.get(map, :reason) ||
      Map.get(map, "reason") ||
      if(is_atom(Map.get(map, :message)), do: Map.get(map, :message), else: nil) ||
      if(is_atom(Map.get(map, "message")), do: Map.get(map, "message"), else: nil)
  end

  defp extract_nested_reason(_), do: nil

  defp extract_retry_value(%{} = map) do
    cond do
      Map.has_key?(map, :retry) -> Map.get(map, :retry)
      Map.has_key?(map, "retry") -> Map.get(map, "retry")
      true -> nil
    end
  end

  defp extract_retry_value(keyword) when is_list(keyword) do
    if Keyword.keyword?(keyword), do: Keyword.get(keyword, :retry), else: nil
  end

  defp extract_retry_value(_), do: nil

  defp retryable_type?(type) when type in [:timeout, :transient, :transient_error, :rate_limited], do: true
  defp retryable_type?(_type), do: false
end
