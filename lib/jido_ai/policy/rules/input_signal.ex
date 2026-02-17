defmodule Jido.AI.Policy.Rules.InputSignal do
  @moduledoc false

  alias Jido.AI.Policy.Engine
  alias Jido.Signal

  @spec start_signal?(String.t()) :: boolean()
  def start_signal?(type) when is_binary(type) do
    String.starts_with?(type, "ai.") and String.ends_with?(type, ".query")
  end

  def start_signal?(_), do: false

  @spec apply(Signal.t(), map()) :: Engine.rule_decision()
  def apply(%Signal{} = signal, config) do
    prompt = extract_prompt(signal)

    with {:ok, prompt} <- validate_prompt(prompt, config),
         {sanitized_prompt, _changed?} <- sanitize_query(prompt, config),
         :ok <- validate_post_sanitize(sanitized_prompt, config) do
      {:continue, put_sanitized_prompt(signal, sanitized_prompt)}
    else
      {:error, reason, message, details} ->
        violation = Engine.violation(:input_signal, reason, message, details)
        rewritten = to_request_error(signal, config)
        {:rewrite, rewritten, violation}
    end
  end

  defp extract_prompt(%Signal{data: data}) do
    Engine.get_data(data, :query) || Engine.get_data(data, :prompt)
  end

  defp validate_prompt(nil, _config), do: {:error, :missing_prompt, "Missing prompt/query", %{}}
  defp validate_prompt("", _config), do: {:error, :empty_prompt, "Prompt cannot be empty", %{}}

  defp validate_prompt(prompt, _config) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      {:error, :empty_prompt, "Prompt cannot be empty", %{}}
    else
      {:ok, prompt}
    end
  end

  defp validate_prompt(_prompt, _config) do
    {:error, :invalid_prompt_type, "Prompt must be a string", %{}}
  end

  defp validate_post_sanitize(prompt, config) do
    cond do
      String.trim(prompt) == "" ->
        {:error, :empty_prompt, "Prompt cannot be empty", %{}}

      String.length(prompt) > max_query_length(config) ->
        {:error, :prompt_too_long, "Prompt exceeds policy length limit", %{max: max_query_length(config)}}

      Map.get(config, :block_injection_patterns, true) and Engine.contains_injection_pattern?(prompt) ->
        {:error, :prompt_injection_detected, "Prompt matched blocked injection patterns", %{}}

      true ->
        :ok
    end
  end

  defp put_sanitized_prompt(%Signal{data: data} = signal, prompt) when is_map(data) do
    data =
      data
      |> maybe_put(:query, prompt)
      |> maybe_put(:prompt, prompt)

    %{signal | data: data}
  end

  defp put_sanitized_prompt(signal, _prompt), do: signal

  defp maybe_put(data, key, value) do
    if Engine.get_data(data, key) do
      Engine.put_data(data, key, value)
    else
      data
    end
  end

  defp to_request_error(%Signal{} = signal, config) do
    request_id = request_id_from_signal(signal)

    message =
      if Map.get(config, :redact_violation_details, true) do
        "Request blocked by policy"
      else
        "Request violated policy checks"
      end

    %{
      signal
      | type: "ai.request.error",
        source: "/ai/policy",
        data: %{request_id: request_id, reason: :policy_violation, message: message}
    }
  end

  defp request_id_from_signal(%Signal{data: data, id: signal_id}) do
    case Engine.string_or_nil(Engine.get_data(data, :request_id)) do
      nil -> signal_id
      request_id -> request_id
    end
  end

  defp sanitize_query(prompt, config) do
    Engine.sanitize_text(prompt, String.length(prompt), config)
  end

  defp max_query_length(config), do: Map.get(config, :query_max_length, 100_000)
end
