defmodule Jido.AI.Plugins.Quota do
  @moduledoc """
  Quota configuration, live admission and correlated model accounting.

  Supervise `Jido.AI.Quota.Store` before use. Use keyword configuration.
  Status/reset routes use a declared result field, default
  `:result`. Pure preparation binds policy; live admission checks current usage.
  Each guarded provider invocation rechecks the shared budget atomically and
  records known usage before the Agent commit. Failed or cancelled calls with no
  usage remain explicit unknown records. Transport retries are part of one call.
  """
  use Jido.Plugin,
    agent: Jido.AI.Plugins.Quota.Agent,
    agent_server: Jido.AI.Plugins.Quota.AgentServer

  alias Jido.AI.Quota.Store
  alias Jido.AI.Actions.Quota.{GetStatus, Reset}

  @defaults %{
    enabled: true,
    scope: nil,
    window_ms: 60_000,
    max_requests: nil,
    max_total_tokens: nil,
    error_message: "quota exceeded for current window"
  }
  @budgeted [
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
  @routes %{"quota.status" => GetStatus, "quota.reset" => Reset}

  def name, do: "quota"
  def description, do: "Tracks usage and enforces rolling request/token budgets"
  def category, do: "ai"
  def tags, do: ["quota", "budget", "usage"]
  def vsn, do: "1.0.0"
  def state_key, do: :quota
  def actions, do: [GetStatus, Reset]

  def signal_routes(_),
    do: Enum.map(["quota.status", "quota.reset"], &{&1, Jido.AI.Actions.Quota.RunCapability})

  def schema, do: state_schema(@defaults)

  @doc false
  def agent_state_spec(opts) do
    Jido.AI.PluginConfig.validate!(opts, Map.keys(@defaults) ++ [:store, :into], "Quota")

    for key <- [:store, :into] do
      value = Keyword.get(opts, key, if(key == :store, do: Store, else: :result))

      unless is_atom(value) and value not in [nil, true, false],
        do: raise(ArgumentError, "Quota #{key} must be an atom")
    end

    case Zoi.parse(schema(), opts |> Keyword.drop([:store, :into]) |> Map.new()) do
      {:ok, defaults} -> {:quota, state_schema(defaults)}
      {:error, errors} -> raise ArgumentError, "Invalid Quota configuration: #{inspect(errors)}"
    end
  end

  defp state_schema(defaults) do
    Zoi.object(%{
      enabled: Zoi.boolean() |> Zoi.default(defaults.enabled),
      scope: Zoi.string() |> Zoi.optional() |> Zoi.default(defaults.scope),
      window_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.window_ms),
      max_requests: Zoi.integer() |> Zoi.min(0) |> Zoi.optional() |> Zoi.default(defaults.max_requests),
      max_total_tokens: Zoi.integer() |> Zoi.min(0) |> Zoi.optional() |> Zoi.default(defaults.max_total_tokens),
      error_message: Zoi.string() |> Zoi.default(defaults.error_message)
    })
    |> Zoi.default(defaults)
  end

  @doc false
  def prepare_input(preparation, opts) do
    state = effective_state(preparation.plugin_state, preparation.agent_id)

    capability =
      if action = @routes[preparation.signal.type],
        do: %{
          action: action,
          defaults: state,
          key: :quota,
          store: Keyword.get(opts, :store, Store),
          into: Keyword.get(opts, :into, :result)
        }

    {:ok, %{binding: binding(preparation, opts), capability: capability}}
  end

  @doc false
  def admit_input(admission) do
    prepared = admission.prepared_input.binding

    binding = %{
      prepared
      | enabled:
          admission.plugin_state.enabled and
            (prepared.enabled or Jido.AI.Runtime.Plugin.native_request?(admission))
    }

    cond do
      admission.signal.type == "ai.usage" and is_map(admission.signal.data) ->
        data = admission.signal.data

        id =
          Map.get(data, :call_id, Map.get(data, "call_id")) ||
            Jido.AI.Signal.Helpers.correlation_id(data) || admission.signal.id

        _ =
          Store.record_usage(
            binding.scope,
            to_string(id),
            Jido.AI.Quota.total_tokens(data),
            binding.window_ms,
            binding.store
          )

        {:ok, %{binding: binding}}

      binding.enabled and
          Store.status(binding.scope, binding, binding.window_ms, binding.store).over_budget? ->
        {:error, Jido.AI.Quota.error(binding)}

      true ->
        {:ok, %{binding: binding}}
    end
  end

  @doc false
  def binding_for_agent(%Jido.Agent{} = agent, signal) do
    case Enum.find(agent.plugins, &(elem(&1, 0) == __MODULE__)) do
      {__MODULE__, opts} ->
        state = agent.state.quota
        prepared = binding(%{plugin_state: state, agent_id: agent.id, signal: signal}, opts)

        %{
          prepared
          | enabled:
              state.enabled and
                (prepared.enabled or not is_nil(Jido.AI.Runtime.Binding.request(agent, signal)))
        }

      nil ->
        nil
    end
  end

  defp effective_state(state, agent_id), do: %{state | scope: state.scope || agent_id || "default"}

  defp binding(preparation, opts) do
    state = effective_state(preparation.plugin_state, preparation.agent_id)
    type = preparation.signal.type

    budgeted =
      type in @budgeted or
        (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run")) or
        (String.starts_with?(type, "ai.") and String.ends_with?(type, ".query"))

    state
    |> Map.put(:enabled, state.enabled and budgeted)
    |> Map.put(:store, Keyword.get(opts, :store, Store))
    |> Map.put(
      :request_id,
      Jido.AI.Signal.Helpers.correlation_id(preparation.signal.data) || preparation.signal.id
    )
    |> Map.put(:signal_type, type)
  end
end
