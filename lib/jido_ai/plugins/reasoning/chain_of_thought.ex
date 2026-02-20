require Jido.AI.Actions.Reasoning.RunStrategy

defmodule Jido.AI.Plugins.Reasoning.ChainOfThought do
  @moduledoc """
  Plugin capability for isolated Chain-of-Thought runs.
  """

  use Jido.Plugin,
    name: "reasoning_chain_of_thought",
    state_key: :reasoning_cot,
    actions: [Jido.AI.Actions.Reasoning.RunStrategy],
    description: "Runs Chain-of-Thought reasoning as a plugin capability",
    category: "ai",
    tags: ["reasoning", "cot", "strategies"],
    vsn: "2.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    {:ok,
     %{
       strategy: :cot,
       default_model: Map.get(config, :default_model, :reasoning),
       timeout: Map.get(config, :timeout, 30_000),
       options: Map.get(config, :options, %{})
     }}
  end

  def schema do
    Zoi.object(%{
      strategy: Zoi.atom(description: "Fixed strategy id") |> Zoi.default(:cot),
      default_model: Zoi.any(description: "Default model alias/spec") |> Zoi.default(:reasoning),
      timeout: Zoi.integer(description: "Default timeout in ms") |> Zoi.default(30_000),
      options: Zoi.map(description: "Default strategy options") |> Zoi.default(%{})
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"reasoning.cot.run", Jido.AI.Actions.Reasoning.RunStrategy}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(%Jido.Signal{type: "reasoning.cot.run", data: data}, _context) do
    params = normalize_map(data) |> Map.put(:strategy, :cot)
    {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}}
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  @impl Jido.Plugin
  def transform_result(_action, result, _context), do: result

  def signal_patterns do
    ["reasoning.cot.run"]
  end

  defp normalize_map(data) when is_map(data), do: data
  defp normalize_map(_), do: %{}
end
