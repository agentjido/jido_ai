defmodule Jido.AI.CLI.Adapters.Adaptive do
  @moduledoc """
  CLI adapter for Adaptive strategy agents.

  Handles the specifics of Adaptive agent lifecycle:
  - Uses `ask/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  - Reports selected strategy in metadata
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model "anthropic:claude-haiku-4-5"
  @default_strategy :react
  @default_available_strategies [:cot, :react, :tot, :got, :trm]

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    agent_module = config.agent_module
    agent_module.ask(pid, query)
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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"Adaptive#{suffix}"])

    model = config[:model] || @default_model
    default_strategy = config[:default_strategy] || @default_strategy
    available_strategies = config[:available_strategies] || @default_available_strategies

    contents =
      quote do
        use Jido.AI.AdaptiveAgent,
          name: "cli_adaptive_agent",
          description: "CLI ephemeral Adaptive agent",
          model: unquote(model),
          default_strategy: unquote(default_strategy),
          available_strategies: unquote(available_strategies)
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
    strategy_state = Map.get(status.raw_state, :__strategy__, %{})

    %{
      status: status.snapshot.status,
      selected_strategy: Map.get(strategy_state, :strategy_type),
      complexity_score: Map.get(strategy_state, :complexity_score),
      task_type: Map.get(strategy_state, :task_type),
      available_strategies: Map.get(details, :available_strategies, [])
    }
  end
end
