defmodule Jido.AI.Plugins.Policy do
  @moduledoc """
  Cross-cutting policy enforcement plugin for inbound AI/runtime signals.
  """

  use Jido.Plugin,
    name: "policy",
    state_key: :policy,
    actions: [],
    description: "Enforces policy checks and normalizes runtime signal envelopes",
    category: "ai",
    tags: ["policy", "guardrails", "safety"],
    vsn: "1.0.0"

  alias Jido.AI.Signal
  alias Jido.AI.Signals.Helpers, as: SignalHelpers
  alias Jido.AI.Validation
  alias Jido.Signal, as: BaseSignal

  @enforceable_request_signals [
    "chat.message",
    "chat.simple",
    "chat.complete",
    "chat.generate_object",
    "ai.react.query",
    "ai.aot.query",
    "ai.cot.query",
    "ai.tot.query",
    "ai.got.query",
    "ai.trm.query",
    "ai.adaptive.query"
  ]

  @impl true
  def mount(_agent, config) do
    {:ok,
     %{
       mode: Map.get(config, :mode, :enforce),
       max_delta_chars: Map.get(config, :max_delta_chars, 4_000),
       block_on_validation_error: Map.get(config, :block_on_validation_error, true)
     }}
  end

  def schema do
    Zoi.object(%{
      mode: Zoi.atom(description: "Policy mode (:enforce or :monitor)") |> Zoi.default(:enforce),
      max_delta_chars: Zoi.integer(description: "Max chars kept in ai.llm.delta payloads") |> Zoi.default(4_000),
      block_on_validation_error:
        Zoi.boolean(description: "Block request/query/chat signals on validation failures")
        |> Zoi.default(true)
    })
  end

  @impl true
  def handle_signal(%BaseSignal{} = signal, context) do
    state = plugin_state(context)
    mode = state[:mode] || :enforce
    max_delta_chars = state[:max_delta_chars] || 4_000

    cond do
      signal.type == "ai.llm.delta" ->
        {:ok, {:continue, sanitize_llm_delta(signal, max_delta_chars)}}

      signal.type in ["ai.llm.response", "ai.tool.result"] ->
        {:ok, {:continue, normalize_result_signal(signal)}}

      mode == :enforce and should_block_signal?(signal, state) ->
        {:ok, {:continue, rewrite_policy_violation(signal)}}

      true ->
        {:ok, :continue}
    end
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  defp should_block_signal?(%BaseSignal{} = signal, state) do
    state[:block_on_validation_error] == true and
      enforceable_request_signal?(signal.type) and
      policy_violation?(signal)
  end

  defp enforceable_request_signal?(type) when is_binary(type) do
    type in @enforceable_request_signals or
      (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run"))
  end

  defp enforceable_request_signal?(_), do: false

  defp policy_violation?(%BaseSignal{data: data}) when is_map(data) do
    prompt_or_query =
      first_present([
        Map.get(data, :prompt),
        Map.get(data, "prompt"),
        Map.get(data, :query),
        Map.get(data, "query")
      ])

    case prompt_or_query do
      text when is_binary(text) and text != "" ->
        case Validation.validate_prompt(text) do
          :ok -> false
          {:error, _} -> true
        end

      _ ->
        false
    end
  end

  defp policy_violation?(_), do: false

  defp rewrite_policy_violation(%BaseSignal{} = signal) do
    request_id = SignalHelpers.correlation_id(signal.data) || "req_#{Jido.Util.generate_id()}"

    Signal.RequestError.new!(%{
      request_id: request_id,
      reason: :policy_violation,
      message: "request blocked by policy"
    })
  end

  defp normalize_result_signal(%BaseSignal{data: data} = signal) when is_map(data) do
    normalized =
      data
      |> Map.get(:result, Map.get(data, "result"))
      |> SignalHelpers.normalize_result(:malformed_result, "Malformed result envelope")

    put_signal_data(signal, Map.put(data, :result, normalized))
  end

  defp normalize_result_signal(signal), do: signal

  defp sanitize_llm_delta(%BaseSignal{data: data} = signal, max_delta_chars) when is_map(data) do
    delta = Map.get(data, :delta, Map.get(data, "delta", ""))
    sanitized = SignalHelpers.sanitize_delta(delta, max_delta_chars)
    put_signal_data(signal, Map.put(data, :delta, sanitized))
  end

  defp sanitize_llm_delta(signal, _), do: signal

  defp put_signal_data(%BaseSignal{} = signal, data), do: %{signal | data: data}

  defp plugin_state(%{agent: %{state: state}, plugin_instance: %{state_key: state_key}})
       when is_map(state) and is_atom(state_key) do
    Map.get(state, state_key, %{})
  end

  defp plugin_state(_), do: %{}

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
