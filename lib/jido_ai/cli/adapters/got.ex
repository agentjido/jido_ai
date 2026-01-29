defmodule Jido.AI.CLI.Adapters.GoT do
  @moduledoc """
  CLI adapter for Graph-of-Thoughts-style agents.

  Handles the specifics of GoT agent lifecycle:
  - Uses `explore/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_nodes 20
  @default_max_depth 5
  @default_aggregation_strategy :synthesis

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
    poll_interval = 100
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    poll_loop(pid, deadline, poll_interval)
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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"GoT#{suffix}"])

    model = config[:model] || @default_model
    max_nodes = config[:max_nodes] || @default_max_nodes
    max_depth = config[:max_depth] || @default_max_depth
    aggregation_strategy = config[:aggregation_strategy] || @default_aggregation_strategy

    contents =
      quote do
        use Jido.AI.GoTAgent,
          name: "cli_got_agent",
          description: "CLI ephemeral GoT agent",
          model: unquote(model),
          max_nodes: unquote(max_nodes),
          max_depth: unquote(max_depth),
          aggregation_strategy: unquote(aggregation_strategy)
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  defp poll_loop(pid, deadline, interval) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case Jido.AgentServer.status(pid) do
        {:ok, status} ->
          if status.snapshot.done? do
            answer =
              case status.snapshot.result do
                nil -> Map.get(status.raw_state, :last_result, "")
                "" -> Map.get(status.raw_state, :last_result, "")
                result -> result
              end

            {:ok, %{answer: answer, meta: extract_meta(status)}}
          else
            Process.sleep(interval)
            poll_loop(pid, deadline, interval)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_meta(status) do
    details = status.snapshot.details || %{}

    %{
      status: status.snapshot.status,
      node_count: Map.get(details, :node_count, 0),
      edge_count: Map.get(details, :edge_count, 0),
      aggregation_strategy: Map.get(details, :aggregation_strategy)
    }
  end
end
