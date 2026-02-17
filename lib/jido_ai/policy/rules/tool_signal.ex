defmodule Jido.AI.Policy.Rules.ToolSignal do
  @moduledoc false

  alias Jido.AI.Policy.Engine
  alias Jido.Signal

  @spec apply(Signal.t(), map()) :: Engine.rule_decision()
  def apply(%Signal{data: data} = signal, config) do
    result = Engine.get_data(data, :result)

    if Engine.valid_result_shape?(result) do
      {sanitized_result, changed?} = Engine.sanitize_result(result, config)

      if changed? do
        rewritten_signal = %{signal | data: Engine.put_data(data, :result, sanitized_result)}

        violation =
          Engine.violation(
            :tool_signal,
            :tool_result_sanitized,
            "Tool result payload was sanitized by policy",
            %{max_length: Map.get(config, :result_max_length, 50_000)}
          )

        {:rewrite, rewritten_signal, violation}
      else
        {:continue, signal}
      end
    else
      policy_result =
        Engine.policy_error(
          :invalid_tool_result,
          "Malformed tool result payload",
          %{},
          config
        )

      rewritten_signal = %{signal | data: Engine.put_data(data, :result, policy_result)}
      violation = Engine.violation(:tool_signal, :invalid_tool_result, "Malformed tool result payload", %{})

      {:rewrite, rewritten_signal, violation}
    end
  end
end
