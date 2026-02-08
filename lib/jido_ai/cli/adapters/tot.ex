defmodule Jido.AI.CLI.Adapters.ToT do
  @moduledoc """
  CLI adapter for Tree-of-Thoughts-style agents.

  Handles the specifics of ToT agent lifecycle:
  - Uses `explore/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter
  alias Jido.AI.CLI.Adapters.Polling

  @default_model "anthropic:claude-haiku-4-5"
  @default_branching_factor 3
  @default_max_depth 3
  @default_traversal_strategy :best_first

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    agent_module = config.agent_module
    agent_module.explore(pid, query)
  end

  @impl true
  def await(pid, timeout_ms, _config) do
    Polling.await(pid, timeout_ms, :last_result, &extract_meta/1)
  end

  @impl true
  def stop(pid) do
    try do
      GenServer.stop(pid, :normal, 1000)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  @impl true
  def create_ephemeral_agent(config) do
    suffix = :erlang.unique_integer([:positive])
    module_name = Module.concat([JidoAi, EphemeralAgent, :"ToT#{suffix}"])

    model = config[:model] || @default_model
    branching_factor = config[:branching_factor] || @default_branching_factor
    max_depth = config[:max_depth] || @default_max_depth
    traversal_strategy = config[:traversal_strategy] || @default_traversal_strategy

    contents =
      quote do
        use Jido.AI.ToTAgent,
          name: "cli_tot_agent",
          description: "CLI ephemeral ToT agent",
          model: unquote(model),
          branching_factor: unquote(branching_factor),
          max_depth: unquote(max_depth),
          traversal_strategy: unquote(traversal_strategy)
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  defp extract_meta(status) do
    details = status.snapshot.details || %{}

    %{
      status: status.snapshot.status,
      node_count: Map.get(details, :node_count, 0),
      traversal_strategy: Map.get(details, :traversal_strategy),
      solution_path_length: length(Map.get(details, :solution_path, []))
    }
  end
end
