defmodule Jido.AI.Policy.Engine do
  @moduledoc """
  Shared policy engine used by `Jido.AI.Plugins.Policy`.

  The engine dispatches AI signals to specialized rule modules and translates
  rule decisions into plugin hook responses.
  """

  alias Jido.AI.Policy.Rules.InputSignal
  alias Jido.AI.Policy.Rules.LLMSignal
  alias Jido.AI.Policy.Rules.ToolSignal
  alias Jido.Signal

  @control_chars ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u

  @injection_patterns [
    ~r/ignore\s+(the\s+)?(previous|above)\s+instructions/i,
    ~r/ignore\s+all\s+(previous|above)?\s+instructions/i,
    ~r/override\s+(your\s+)?system/i,
    ~r/disregard\s+(the\s+)?(previous|above)\s+instructions/i,
    ~r/disregard\s+all\s+(previous|above)?\s+instructions/i,
    ~r/pay\s+no\s+attention\s+to\s+(the\s+)?(previous|above)/i,
    ~r/forget\s+(everything|all\s+instructions)/i,
    ~r/\n\n\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
    ~r/###\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
    ~r/---\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
    ~r/you\s+are\s+now\s+a\s+(different|new)/i,
    ~r/act\s+as\s+if\s+you\s+are/i,
    ~r/pretend\s+(to\s+be|you\s+are)/i,
    ~r/switch\s+roles?\s+with\s+me/i,
    ~r/roleplay\s+as\s+(a\s+)?(different|new|dangerous)/i,
    ~r/\{[^}]*"role"\s*:\s*"system"/i,
    ~r/<[^>]*system[^>]*>/i,
    ~r/dan\s+\d+\.?\d*/i,
    ~r/(developer|admin|root)\s+mode/i,
    ~r/unrestricted\s+mode/i,
    ~r/bypass\s+(all\s+)?(safety|filters?|security)/i,
    ~r/(print|output|display|say|echo)\s+(everything|all\s+the\s+(above|text|instructions))/i,
    ~r/(repeat|return|show)\s+your\s+(system\s+)?prompt/i,
    ~r/translate\s+(this|the\s+above)\s+to\s+(base64|binary|hex)/i
  ]

  @type violation :: %{
          rule: atom(),
          reason: atom(),
          message: String.t(),
          details: map()
        }

  @type rule_decision ::
          {:continue, Signal.t()}
          | {:rewrite, Signal.t(), violation()}
          | {:override, module() | {module(), map()}, violation()}

  @spec handle(Signal.t(), map()) :: {:ok, term()}
  def handle(%Signal{type: "ai.request.error"} = signal, _config) do
    {:ok, {:continue, signal}}
  end

  def handle(%Signal{} = signal, config) do
    signal
    |> decide(config)
    |> apply_mode(signal, config)
  end

  @spec violation(atom(), atom(), String.t(), map()) :: violation()
  def violation(rule, reason, message, details \\ %{}) do
    %{rule: rule, reason: reason, message: message, details: details}
  end

  @spec get_data(map() | nil, atom(), term()) :: term()
  def get_data(data, key, default \\ nil)
  def get_data(data, _key, default) when not is_map(data), do: default

  def get_data(data, key, default) do
    case Map.fetch(data, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(data, Atom.to_string(key), default)
    end
  end

  @spec put_data(map() | nil, atom(), term()) :: map()
  def put_data(data, key, value) when is_map(data) do
    cond do
      Map.has_key?(data, key) and Map.has_key?(data, Atom.to_string(key)) ->
        data
        |> Map.put(key, value)
        |> Map.put(Atom.to_string(key), value)

      Map.has_key?(data, key) ->
        Map.put(data, key, value)

      Map.has_key?(data, Atom.to_string(key)) ->
        Map.put(data, Atom.to_string(key), value)

      true ->
        Map.put(data, key, value)
    end
  end

  def put_data(_data, key, value), do: %{key => value}

  @spec contains_injection_pattern?(String.t()) :: boolean()
  def contains_injection_pattern?(prompt) when is_binary(prompt) do
    Enum.any?(@injection_patterns, &Regex.match?(&1, prompt))
  end

  @spec sanitize_text(String.t(), pos_integer(), map()) :: {String.t(), boolean()}
  def sanitize_text(text, max_length, config) when is_binary(text) do
    stripped =
      if Map.get(config, :strip_control_chars, true) do
        strip_control_chars(text)
      else
        text
      end

    truncated =
      if String.length(stripped) > max_length do
        String.slice(stripped, 0, max_length)
      else
        stripped
      end

    {truncated, truncated != text}
  end

  @spec sanitize_result(tuple(), map()) :: {tuple(), boolean()}
  def sanitize_result({status, payload} = result, config) when status in [:ok, :error] do
    max_length = Map.get(config, :result_max_length, 50_000)
    {sanitized_payload, changed?} = sanitize_term(payload, max_length, config)

    if changed? do
      {{status, sanitized_payload}, true}
    else
      {result, false}
    end
  end

  def sanitize_result(result, _config), do: {result, false}

  @spec policy_error(tuple() | atom(), String.t(), map(), map()) :: tuple()
  def policy_error(reason, message, details, config) do
    safe_details = redact_details(details, config)

    safe_message =
      if Map.get(config, :redact_violation_details, true) do
        "Blocked by policy"
      else
        message
      end

    {:error,
     %{
       type: :policy_violation,
       reason: reason,
       message: safe_message,
       details: safe_details
     }}
  end

  @spec valid_result_shape?(term()) :: boolean()
  def valid_result_shape?({status, _payload}) when status in [:ok, :error], do: true
  def valid_result_shape?(_), do: false

  @spec redact_details(map(), map()) :: map()
  def redact_details(details, config) do
    if Map.get(config, :redact_violation_details, true) do
      %{redacted: true}
    else
      details
    end
  end

  @spec string_or_nil(term()) :: String.t() | nil
  def string_or_nil(value) when is_binary(value), do: value
  def string_or_nil(_), do: nil

  defp decide(%Signal{} = signal, config) do
    cond do
      InputSignal.start_signal?(signal.type) ->
        InputSignal.apply(signal, config)

      signal.type in ["ai.llm.delta", "ai.llm.response"] ->
        LLMSignal.apply(signal, config)

      signal.type == "ai.tool.result" ->
        ToolSignal.apply(signal, config)

      true ->
        {:continue, signal}
    end
  end

  defp apply_mode({:continue, signal}, _original, _config) do
    {:ok, {:continue, signal}}
  end

  defp apply_mode({:rewrite, signal, violation}, original_signal, config) do
    mode = Map.get(config, :mode, :enforce)
    emit_violation(original_signal, violation, mode, :rewrite, config)

    case mode do
      :report_only -> {:ok, {:continue, original_signal}}
      _ -> {:ok, {:continue, signal}}
    end
  end

  defp apply_mode({:override, action_spec, violation}, original_signal, config) do
    mode = Map.get(config, :mode, :enforce)
    emit_violation(original_signal, violation, mode, :override, config)

    case mode do
      :report_only -> {:ok, {:continue, original_signal}}
      _ -> {:ok, {:override, action_spec}}
    end
  end

  defp emit_violation(signal, violation, mode, action, config) do
    :telemetry.execute(
      [:jido_ai, :policy, :violation],
      %{count: 1},
      %{
        mode: mode,
        action: action,
        signal_type: signal.type,
        signal_id: signal.id,
        rule: violation.rule,
        reason: violation.reason,
        details: redact_details(violation.details, config)
      }
    )
  end

  defp strip_control_chars(text) do
    Regex.replace(@control_chars, text, "")
  end

  defp sanitize_term(value, max_length, config) when is_binary(value) do
    sanitize_text(value, max_length, config)
  end

  defp sanitize_term(value, max_length, config) when is_list(value) do
    Enum.map_reduce(value, false, fn item, changed? ->
      {sanitized_item, item_changed?} = sanitize_term(item, max_length, config)
      {sanitized_item, changed? or item_changed?}
    end)
  end

  defp sanitize_term(%mod{} = value, max_length, config) when is_atom(mod) do
    value
    |> Map.from_struct()
    |> Enum.reduce({value, false}, fn {key, field_value}, {acc, changed?} ->
      {sanitized_field, field_changed?} = sanitize_term(field_value, max_length, config)

      if field_changed? do
        {Map.put(acc, key, sanitized_field), true}
      else
        {acc, changed?}
      end
    end)
  end

  defp sanitize_term(value, max_length, config) when is_map(value) do
    Enum.reduce(value, {%{}, false}, fn {key, field_value}, {acc, changed?} ->
      {sanitized_field, field_changed?} = sanitize_term(field_value, max_length, config)
      {Map.put(acc, key, sanitized_field), changed? or field_changed?}
    end)
  end

  defp sanitize_term(value, _max_length, _config), do: {value, false}
end
