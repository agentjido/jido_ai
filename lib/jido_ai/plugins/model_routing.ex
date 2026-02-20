defmodule Jido.AI.Plugins.ModelRouting do
  @moduledoc """
  Cross-cutting model routing plugin.

  Applies default model aliases by signal intent while respecting explicit
  request-level model overrides.
  """

  use Jido.Plugin,
    name: "model_routing",
    state_key: :model_routing,
    actions: [],
    description: "Routes model selection by signal intent",
    category: "ai",
    tags: ["models", "routing", "policy"],
    vsn: "1.0.0"

  alias Jido.Signal

  @default_routes %{
    "chat.message" => :capable,
    "chat.simple" => :fast,
    "chat.complete" => :fast,
    "chat.embed" => :embedding,
    "chat.generate_object" => :thinking,
    "reasoning.*.run" => :reasoning
  }

  @impl true
  def mount(_agent, config) do
    configured = Map.get(config, :routes, %{})
    routes = Map.merge(@default_routes, normalize_routes(configured))
    {:ok, %{routes: routes}}
  end

  def schema do
    Zoi.object(%{
      routes: Zoi.map(description: "Signal type/pattern to model alias mapping") |> Zoi.default(@default_routes)
    })
  end

  @impl true
  def handle_signal(%Signal{data: data} = signal, context) when is_map(data) do
    if explicit_model?(data) do
      {:ok, :continue}
    else
      routes = routing_table(context)

      case route_model(signal.type, routes) do
        nil ->
          {:ok, :continue}

        model_alias ->
          {:ok, {:continue, %{signal | data: Map.put(data, :model, model_alias)}}}
      end
    end
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  defp route_model(type, routes) when is_binary(type) and is_map(routes) do
    exact = Map.get(routes, type)

    if is_nil(exact) do
      routes
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

  defp normalize_routes(_), do: %{}

  defp routing_table(%{agent: %{state: state}, plugin_instance: %{state_key: state_key}})
       when is_map(state) and is_atom(state_key) do
    state
    |> Map.get(state_key, %{})
    |> Map.get(:routes, @default_routes)
  end

  defp routing_table(_), do: @default_routes
end
