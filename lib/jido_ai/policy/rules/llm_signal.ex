defmodule Jido.AI.Policy.Rules.LLMSignal do
  @moduledoc false

  alias Jido.AI.Policy.Engine
  alias Jido.Signal

  @spec apply(Signal.t(), map()) :: Engine.rule_decision()
  def apply(%Signal{type: "ai.llm.delta"} = signal, config), do: apply_delta(signal, config)
  def apply(%Signal{type: "ai.llm.response"} = signal, config), do: apply_response(signal, config)

  def apply(%Signal{} = signal, _config) do
    {:continue, signal}
  end

  defp apply_delta(%Signal{data: data} = signal, config) do
    case Engine.string_or_nil(Engine.get_data(data, :delta)) do
      nil ->
        violation = Engine.violation(:llm_signal, :invalid_delta_payload, "LLM delta payload is invalid", %{})
        {:override, Jido.Actions.Control.Noop, violation}

      delta ->
        {sanitized_delta, changed?} = Engine.sanitize_text(delta, max_delta_length(config), config)

        cond do
          sanitized_delta == "" ->
            violation = Engine.violation(:llm_signal, :empty_delta, "LLM delta was empty after sanitization", %{})
            {:override, Jido.Actions.Control.Noop, violation}

          changed? ->
            rewritten_signal = %{signal | data: Engine.put_data(data, :delta, sanitized_delta)}

            violation =
              Engine.violation(:llm_signal, :delta_sanitized, "LLM delta was sanitized by policy", %{
                max_length: max_delta_length(config)
              })

            {:rewrite, rewritten_signal, violation}

          true ->
            {:continue, signal}
        end
    end
  end

  defp apply_response(%Signal{data: data} = signal, config) do
    result = Engine.get_data(data, :result)

    if Engine.valid_result_shape?(result) do
      {sanitized_result, changed?} = Engine.sanitize_result(result, config)

      if changed? do
        rewritten_signal = %{signal | data: Engine.put_data(data, :result, sanitized_result)}

        violation =
          Engine.violation(
            :llm_signal,
            :llm_result_sanitized,
            "LLM result payload was sanitized by policy",
            %{max_length: Map.get(config, :result_max_length, 50_000)}
          )

        {:rewrite, rewritten_signal, violation}
      else
        {:continue, signal}
      end
    else
      policy_result =
        Engine.policy_error(
          :invalid_llm_result,
          "Malformed LLM result payload",
          %{},
          config
        )

      rewritten_signal = %{signal | data: Engine.put_data(data, :result, policy_result)}
      violation = Engine.violation(:llm_signal, :invalid_llm_result, "Malformed LLM result payload", %{})

      {:rewrite, rewritten_signal, violation}
    end
  end

  defp max_delta_length(config), do: Map.get(config, :delta_max_length, 4_096)
end
