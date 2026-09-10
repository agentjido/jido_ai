defmodule Jido.AI.Plugins.ModelRouting do
  @moduledoc """
  Cross-cutting model routing plugin.

  Applies default model aliases by signal intent while respecting explicit
  request-level model overrides.

  ## Route Precedence

  Route selection follows deterministic precedence:

  1. Exact signal type route (for example, `"chat.message"`)
  2. Wildcard pattern route (for example, `"reasoning.*.run"`)

  If the inbound payload already includes `:model` (or `"model"`), the plugin
  bypasses routing and preserves the explicit model choice.

  ## Wildcard Contracts

  Wildcard routes use `*` as a single dot-delimited segment matcher.

  - `"reasoning.*.run"` matches `"reasoning.cot.run"` and `"reasoning.tot.run"`
  - `"reasoning.*.run"` does not match `"reasoning.cot.worker.run"`

  ## v3 declaration

  Declare `plugin Jido.AI.Plugins.ModelRouting, config: [routes: routes]`
  inside `agent do`. Configuration is keyword data. Explicit request model
  values win. Exact routes precede wildcard matches; overlapping wildcard
  patterns use lexical order. The Plugin prepares Signal input through core.
  """

  use Jido.Plugin,
    agent: Jido.AI.Plugins.ModelRouting.Agent,
    agent_server: Jido.AI.Plugins.ModelRouting.AgentServer

  def name, do: "model_routing"
  def description, do: "Routes model selection by signal intent"
  def category, do: "ai"
  def tags, do: ["models", "routing", "policy"]
  def vsn, do: "1.0.0"
  def state_key, do: :model_routing
  def actions, do: []

  @default_routes %{
    "chat.message" => :capable,
    "chat.simple" => :fast,
    "chat.complete" => :fast,
    "chat.embed" => :embedding,
    "chat.generate_object" => :thinking,
    "reasoning.*.run" => :reasoning
  }

  @doc false
  def agent_state_spec(opts) do
    Jido.AI.PluginConfig.validate!(opts, [:routes], "ModelRouting")
    configured = Keyword.get(opts, :routes, %{})

    unless is_map(configured) and not is_struct(configured),
      do: raise(ArgumentError, "ModelRouting routes must be a map")

    routes = Map.merge(@default_routes, normalize_routes(configured))
    {:model_routing, state_schema(routes)}
  end

  def schema, do: state_schema(@default_routes)

  defp state_schema(routes),
    do: Zoi.object(%{routes: Zoi.map() |> Zoi.default(routes)}) |> Zoi.default(%{routes: routes})

  @doc false
  def prepare_command(command) do
    signal = command.signal
    data = signal.data
    routes = command.agent.state.model_routing.routes

    request_override? =
      explicit_model?(Map.get(command.context, :jido_ai_request, %{}))

    model =
      if is_map(data) and not explicit_model?(data) and not request_override?,
        do: route_model(signal.type, routes)

    if is_nil(model),
      do: {:ok, command},
      else: {:ok, %{command | signal: %{signal | data: Map.put(data, :model, model)}}}
  end

  defp route_model(type, routes) when is_binary(type) and is_map(routes) do
    exact = Map.get(routes, type)

    if is_nil(exact) do
      routes
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find_value(fn {pattern, model} ->
        if wildcard_match?(type, pattern), do: model, else: nil
      end)
    else
      exact
    end
  end

  defp route_model(_, _), do: nil

  defp wildcard_match?(_type, pattern) when not is_binary(pattern), do: false

  defp wildcard_match?(type, pattern) do
    cond do
      pattern == type ->
        true

      String.contains?(pattern, "*") ->
        regex =
          pattern
          |> Regex.escape()
          |> String.replace("\\*", "[^.]+")

        Regex.match?(~r/^#{regex}$/, type)

      true ->
        false
    end
  end

  defp explicit_model?(data) when is_map(data) do
    model = Map.get(data, :model, Map.get(data, "model"))
    not is_nil(model) and model != ""
  end

  defp normalize_routes(%{} = routes) do
    routes
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      key = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
      Map.put(acc, key, v)
    end)
  end
end

defmodule Jido.AI.Plugins.ModelRouting.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.ModelRouting.agent_state_spec(opts)
end

defmodule Jido.AI.Plugins.ModelRouting.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, command, _opts), do: Jido.AI.Plugins.ModelRouting.prepare_command(command)
end
