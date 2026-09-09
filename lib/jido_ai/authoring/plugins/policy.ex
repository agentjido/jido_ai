defmodule Jido.AI.Plugins.Policy do
  @moduledoc """
  Declared input policy and observation normalization for core Agents.

  Enforce mode returns a canonical non-retryable policy error before execution.
  It retains request correlation and does not rewrite the Signal to another
  route. Monitor mode and `block_on_validation_error: false` permit input.
  Native AI bindings and legacy AI request namespaces share this policy.
  Model/tool results and text deltas retain the existing normalization rules.
  """
  use Jido.Plugin, agent: Jido.AI.Plugins.Policy.Agent
  alias Jido.AI.{Error, Validation}
  alias Jido.AI.Signal.Helpers, as: SignalHelpers
  alias Jido.Signal, as: BaseSignal

  def name, do: "policy"
  def description, do: "Enforces policy checks and normalizes runtime signal envelopes"
  def category, do: "ai"
  def tags, do: ["policy", "guardrails", "safety"]
  def vsn, do: "1.0.0"
  def state_key, do: :policy
  def actions, do: []
  @defaults %{mode: :enforce, max_delta_chars: 4000, block_on_validation_error: true}

  @enforceable_request_signals [
    "chat.message",
    "chat.simple",
    "chat.complete",
    "chat.generate_object",
    "ai.react.query",
    "ai.cod.query",
    "ai.aot.query",
    "ai.cot.query",
    "ai.tot.query",
    "ai.got.query",
    "ai.trm.query",
    "ai.adaptive.query"
  ]

  @doc false
  def agent_state_spec(opts) do
    Jido.AI.PluginConfig.validate!(opts, Map.keys(@defaults), "Policy")

    case Zoi.parse(schema(), Map.new(opts)) do
      {:ok, defaults} -> {:policy, state_schema(defaults)}
      {:error, errors} -> raise ArgumentError, "Invalid Policy configuration: #{inspect(errors)}"
    end
  end

  def schema, do: state_schema(@defaults)

  defp state_schema(defaults) do
    Zoi.object(%{
      mode: Zoi.enum([:enforce, :monitor]) |> Zoi.default(defaults.mode),
      max_delta_chars: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.max_delta_chars),
      block_on_validation_error: Zoi.boolean() |> Zoi.default(defaults.block_on_validation_error)
    })
    |> Zoi.default(defaults)
  end

  @doc false
  def prepare_agent(preparation) do
    state = preparation.plugin_state
    signal = preparation.effective_signal

    cond do
      signal.type == "ai.llm.delta" ->
        {:ok, %{preparation | effective_signal: sanitize_llm_delta(signal, state.max_delta_chars)}}

      signal.type in ["ai.llm.response", "ai.tool.result"] ->
        {:ok, %{preparation | effective_signal: normalize_result_signal(signal)}}

      state.mode == :enforce and state.block_on_validation_error and violation?(signal) ->
        {:error, policy_error(signal)}

      true ->
        {:ok, preparation}
    end
  end

  @doc false
  def prepare_bound_command(command) do
    with true <- Enum.any?(command.agent.plugins, &(plugin_module(&1) == __MODULE__)),
         %{input: input} <- Jido.AI.Authoring.request_binding(command.agent, command.signal),
         %{mode: mode, block_on_validation_error: block?} <- command.agent.state[state_key()],
         true <- mode == :enforce and block?,
         signal = %{command.signal | data: input},
         true <- policy_violation?(signal) do
      {:error, policy_error(signal)}
    else
      _ -> {:ok, command}
    end
  end

  defp violation?(signal),
    do: enforceable_request_signal?(signal.type) and policy_violation?(signal)

  defp query_text(value) when is_binary(value), do: value

  defp query_text(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      %{type: type, text: text}
      when type in [:text, :thinking, "text", "thinking"] and is_binary(text) ->
        [text]

      %{"type" => type, "text" => text} when type in ["text", "thinking"] and is_binary(text) ->
        [text]

      _ ->
        []
    end)
    |> Enum.join("\n")
  end

  defp query_text(_), do: nil

  defp invalid_text?(text) when is_binary(text) and text != "",
    do: Validation.validate_prompt(text) != :ok

  defp invalid_text?(_), do: false

  defp enforceable_request_signal?(type) when is_binary(type) do
    type in @enforceable_request_signals or
      (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run"))
  end

  defp enforceable_request_signal?(_), do: false

  defp policy_violation?(%BaseSignal{data: data}) when is_map(data) do
    [
      Map.get(data, :prompt),
      Map.get(data, "prompt"),
      Map.get(data, :query),
      Map.get(data, "query")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&invalid_text?(query_text(&1)))
  end

  defp policy_violation?(_), do: false

  defp policy_error(signal) do
    request_id = SignalHelpers.correlation_id(signal.data) || "req_#{Jido.Signal.ID.generate!()}"

    Error.error_envelope(
      :policy_violation,
      "request blocked by policy",
      %{request_id: request_id, signal_type: signal.type},
      false
    )
  end

  defp normalize_result_signal(%BaseSignal{data: data} = signal) when is_map(data) do
    normalized =
      data
      |> Map.get(:result, Map.get(data, "result"))
      |> Error.normalize_result(:malformed_result, "Malformed result envelope")

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

  defp plugin_module({module, _opts}), do: module
  defp plugin_module(module), do: module
end

defmodule Jido.AI.Plugins.Policy.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Policy.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def prepare(preparation, _opts), do: Jido.AI.Plugins.Policy.prepare_agent(preparation)
end
