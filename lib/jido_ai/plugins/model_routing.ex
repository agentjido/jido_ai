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
  patterns use lexical order. The Plugin prepares a model choice for the Action.
  """

  use Jido.Plugin, agent: Jido.AI.Plugins.ModelRouting.Agent

  @doc "Returns the Plugin name."
  def name, do: "model_routing"
  @doc "Returns a short description of the Plugin."
  def description, do: "Routes model selection by signal intent"
  @doc "Returns the Plugin category."
  def category, do: "ai"
  @doc "Returns tags that classify the Plugin."
  def tags, do: ["models", "routing", "policy"]
  @doc "Returns the Plugin metadata version."
  def vsn, do: "1.0.0"
  @doc "Returns the Agent state key owned by the Plugin."
  def state_key, do: :model_routing
  @doc "Returns the Actions exposed by the Plugin."
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

  @doc "Returns the schema for the Plugin's state."
  def schema, do: state_schema(@default_routes)

  defp state_schema(routes),
    do: Zoi.object(%{routes: Zoi.map() |> Zoi.default(routes)}) |> Zoi.default(%{routes: routes})

  @doc false
  def prepare_input(preparation) do
    signal = preparation.signal
    data = signal.data
    routes = preparation.plugin_state.routes

    model =
      if is_map(data) and not explicit_model?(data),
        do: route_model(signal.type, routes)

    {:ok, model}
  end

  @doc false
  def selected_for_agent(agent, signal) do
    if Enum.any?(agent.plugins, &(elem(&1, 0) == __MODULE__)) do
      case Map.get(agent.state, state_key()) do
        %{routes: routes} ->
          {:ok, model} = prepare_input(%{signal: signal, plugin_state: %{routes: routes}})
          model

        _ ->
          nil
      end
    end
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
