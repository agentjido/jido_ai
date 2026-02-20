require Jido.AI.Actions.Reasoning.RunStrategy

defmodule Jido.AI.Plugins.Reasoning.GraphOfThoughts do
  @moduledoc """
  Plugin capability for isolated Graph-of-Thoughts runs.

  ## Signal Contracts

  - `reasoning.got.run` -> `Jido.AI.Actions.Reasoning.RunStrategy`

  ## Plugin-To-Action Handoff

  This plugin always overrides the runtime strategy identity to `:got`.
  On `reasoning.got.run`, `handle_signal/2` returns:

  - `{:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}`
  - `params` always includes `strategy: :got` (caller strategy input is ignored)

  `Jido.AI.Actions.Reasoning.RunStrategy` consumes the normalized params
  and applies plugin defaults from context when explicit params are omitted.

  ## Usage

  Mount in an agent with fixed GoT defaults:

      plugins: [
        {Jido.AI.Plugins.Reasoning.GraphOfThoughts,
         %{
           default_model: :reasoning,
           timeout: 30_000,
           options: %{max_nodes: 20, max_depth: 5, aggregation_strategy: :synthesis}
         }}
      ]

  Then send `reasoning.got.run` with caller input; plugin enforces `strategy: :got`.

  ## GoT Options

  Use `options` for default GoT controls consumed by `RunStrategy`:

  - `max_nodes`
  - `max_depth`
  - `aggregation_strategy`
  - `generation_prompt`
  - `connection_prompt`
  - `aggregation_prompt`

  ## Mount State Defaults

  - `strategy`: `:got`
  - `default_model`: `:reasoning`
  - `timeout`: `30_000`
  - `options`: `%{}`
  """

  use Jido.Plugin,
    name: "reasoning_graph_of_thoughts",
    state_key: :reasoning_got,
    actions: [Jido.AI.Actions.Reasoning.RunStrategy],
    description: "Runs Graph-of-Thoughts reasoning as a plugin capability",
    category: "ai",
    tags: ["reasoning", "got", "strategies"],
    vsn: "2.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    {:ok,
     %{
       strategy: :got,
       default_model: Map.get(config, :default_model, :reasoning),
       timeout: Map.get(config, :timeout, 30_000),
       options: Map.get(config, :options, %{})
     }}
  end

  def schema do
    Zoi.object(%{
      strategy: Zoi.atom(description: "Fixed strategy id") |> Zoi.default(:got),
      default_model: Zoi.any(description: "Default model alias/spec") |> Zoi.default(:reasoning),
      timeout: Zoi.integer(description: "Default timeout in ms") |> Zoi.default(30_000),
      options: Zoi.map(description: "Default strategy options") |> Zoi.default(%{})
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"reasoning.got.run", Jido.AI.Actions.Reasoning.RunStrategy}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(%Jido.Signal{type: "reasoning.got.run", data: data}, _context) do
    params = normalize_map(data) |> Map.put(:strategy, :got)
    {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}}
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  @impl Jido.Plugin
  def transform_result(_action, result, _context), do: result

  def signal_patterns do
    ["reasoning.got.run"]
  end

  defp normalize_map(data) when is_map(data), do: data
  defp normalize_map(_), do: %{}
end
