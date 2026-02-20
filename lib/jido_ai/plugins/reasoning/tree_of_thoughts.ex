require Jido.AI.Actions.Reasoning.RunStrategy

defmodule Jido.AI.Plugins.Reasoning.TreeOfThoughts do
  @moduledoc """
  Plugin capability for isolated Tree-of-Thoughts runs.

  ## Signal Contracts

  - `reasoning.tot.run` -> `Jido.AI.Actions.Reasoning.RunStrategy`

  ## Plugin-To-Action Handoff

  This plugin always overrides the runtime strategy identity to `:tot`.
  On `reasoning.tot.run`, `handle_signal/2` returns:

  - `{:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}`
  - `params` always includes `strategy: :tot` (caller strategy input is ignored)

  `Jido.AI.Actions.Reasoning.RunStrategy` consumes the normalized params
  and applies plugin defaults from context when explicit params are omitted.

  ## Usage

  Mount in an agent with fixed ToT defaults:

      plugins: [
        {Jido.AI.Plugins.Reasoning.TreeOfThoughts,
         %{
           default_model: :reasoning,
           timeout: 30_000,
           options: %{branching_factor: 3, max_depth: 4, traversal_strategy: :best_first}
         }}
      ]

  Then send `reasoning.tot.run` with caller input; plugin enforces `strategy: :tot`.

  ## ToT Options

  Use `options` for default ToT controls consumed by `RunStrategy`:

  - `branching_factor`
  - `max_depth`
  - `traversal_strategy`
  - `generation_prompt`
  - `evaluation_prompt`

  ## Mount State Defaults

  - `strategy`: `:tot`
  - `default_model`: `:reasoning`
  - `timeout`: `30_000`
  - `options`: `%{}`
  """

  use Jido.Plugin,
    name: "reasoning_tree_of_thoughts",
    state_key: :reasoning_tot,
    actions: [Jido.AI.Actions.Reasoning.RunStrategy],
    description: "Runs Tree-of-Thoughts reasoning as a plugin capability",
    category: "ai",
    tags: ["reasoning", "tot", "strategies"],
    vsn: "2.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    {:ok,
     %{
       strategy: :tot,
       default_model: Map.get(config, :default_model, :reasoning),
       timeout: Map.get(config, :timeout, 30_000),
       options: Map.get(config, :options, %{})
     }}
  end

  def schema do
    Zoi.object(%{
      strategy: Zoi.atom(description: "Fixed strategy id") |> Zoi.default(:tot),
      default_model: Zoi.any(description: "Default model alias/spec") |> Zoi.default(:reasoning),
      timeout: Zoi.integer(description: "Default timeout in ms") |> Zoi.default(30_000),
      options: Zoi.map(description: "Default strategy options") |> Zoi.default(%{})
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"reasoning.tot.run", Jido.AI.Actions.Reasoning.RunStrategy}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(%Jido.Signal{type: "reasoning.tot.run", data: data}, _context) do
    params = normalize_map(data) |> Map.put(:strategy, :tot)
    {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}}
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  @impl Jido.Plugin
  def transform_result(_action, result, _context), do: result

  def signal_patterns do
    ["reasoning.tot.run"]
  end

  defp normalize_map(data) when is_map(data), do: data
  defp normalize_map(_), do: %{}
end
