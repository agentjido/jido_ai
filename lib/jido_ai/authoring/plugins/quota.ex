defmodule Jido.AI.Plugins.Quota do
  @moduledoc """
  Quota configuration, live admission and correlated model accounting.

  Supervise `Jido.AI.Quota.Store` before use. Keyword configuration replaces v2
  mount configuration. Status/reset routes use a declared result field, default
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
  def prepare_agent(preparation, opts) do
    state = effective_preparation_state(preparation)

    context =
      preparation.context
      |> Map.put(:quota_store, Keyword.get(opts, :store, Store))
      |> Map.put(:jido_ai_quota, preparation_binding(preparation, opts))
      |> Map.delete(:jido_ai_quota_call_id)

    capability =
      if action = @routes[preparation.effective_signal.type],
        do: %{
          action: action,
          defaults: state,
          key: :quota,
          into: Keyword.get(opts, :into, :result)
        }

    Jido.AI.Capability.bind(
      %{preparation | context: context},
      :jido_ai_quota_capability,
      capability
    )
  end

  @doc false
  def admit_command(command, opts) do
    binding = binding(command, opts)

    cond do
      command.signal.type == "ai.usage" and is_map(command.signal.data) ->
        data = command.signal.data

        id =
          Map.get(data, :call_id, Map.get(data, "call_id")) ||
            Jido.AI.Signal.Helpers.correlation_id(data) || command.signal.id

        _ =
          Store.record_usage(
            binding.scope,
            to_string(id),
            Jido.AI.Quota.total_tokens(data),
            binding.window_ms,
            binding.store
          )

        {:ok, command}

      binding.enabled and
          Store.status(binding.scope, binding, binding.window_ms, binding.store).over_budget? ->
        {:error, Jido.AI.Quota.error(binding)}

      true ->
        {:ok, command}
    end
  end

  defp effective_preparation_state(preparation) do
    state = preparation.plugin_state
    %{state | scope: state.scope || preparation.agent_id || "default"}
  end

  defp effective_command_state(command) do
    state = command.agent.state.quota
    %{state | scope: state.scope || command.agent.id || "default"}
  end

  defp binding(command, opts) do
    state = effective_command_state(command)
    type = command.signal.type

    budgeted =
      type in @budgeted or
        (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run")) or
        not is_nil(Jido.AI.Authoring.request_binding(command.agent, command.signal))

    state
    |> Map.put(:enabled, state.enabled and budgeted)
    |> Map.put(:store, Keyword.get(opts, :store, Store))
    |> Map.put(
      :request_id,
      Jido.AI.Signal.Helpers.correlation_id(command.signal.data) || command.signal.id
    )
    |> Map.put(:signal_type, type)
  end

  @doc false
  def prepare_bound_command(command) do
    case Enum.find(command.agent.plugins, &(plugin_module(&1) == __MODULE__)) do
      {__MODULE__, opts} ->
        {:ok, %{command | context: Map.put(command.context, :jido_ai_quota, binding(command, opts))}}

      __MODULE__ ->
        {:ok, %{command | context: Map.put(command.context, :jido_ai_quota, binding(command, []))}}

      nil ->
        {:ok, command}
    end
  end

  defp plugin_module({module, _opts}), do: module
  defp plugin_module(module), do: module

  defp preparation_binding(preparation, opts) do
    state = effective_preparation_state(preparation)
    signal = preparation.effective_signal
    type = signal.type

    budgeted =
      type in @budgeted or
        (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run"))

    state
    |> Map.put(:enabled, state.enabled and budgeted)
    |> Map.put(:store, Keyword.get(opts, :store, Store))
    |> Map.put(
      :request_id,
      Jido.AI.Signal.Helpers.correlation_id(signal.data) || signal.id
    )
    |> Map.put(:signal_type, type)
  end
end

defmodule Jido.AI.Plugins.Quota.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Quota.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def observes(opts), do: [Keyword.get(opts, :into, :result)]

  @impl Jido.Agent.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Quota.prepare_agent(preparation, opts)
end

defmodule Jido.AI.Plugins.Quota.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, command, opts), do: Jido.AI.Plugins.Quota.admit_command(command, opts)
end
