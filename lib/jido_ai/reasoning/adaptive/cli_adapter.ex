defmodule Jido.AI.Reasoning.Adaptive.CLIAdapter do
  @moduledoc """
  CLI adapter for Adaptive strategy agents.

  Handles the specifics of Adaptive agent lifecycle:
  - Uses `ask/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  - Reports selected strategy in metadata

  AoT is supported when explicitly included in `available_strategies`.
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model :fast
  @default_available_strategies [:cod, :cot, :react, :tot, :got, :trm]

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
    available_strategies = config[:available_strategies] || @default_available_strategies

    Jido.AI.CLI.EphemeralAgent.create(module_name,
      method: :adaptive,
      name: "cli_adaptive_agent",
      description: "CLI ephemeral Adaptive agent",
      model: model,
      reasoning_options: %{available_strategies: available_strategies}
    )
  end

  defp poll_loop(pid, deadline, interval) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case Jido.AI.CLI.Adapter.status(pid) do
        {:ok, status} ->
          if status.snapshot.done? do
            answer = format_cli_answer(status.snapshot.result)

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
    selection = Map.get(details, :adaptive, %{})

    %{
      status: status.snapshot.status,
      selected_strategy: Map.get(selection, :strategy),
      complexity_score: Map.get(selection, :complexity_score),
      task_type: Map.get(selection, :task_type),
      available_strategies: Map.get(details, :available_strategies, [])
    }
  end

  defp format_cli_answer(nil), do: ""
  defp format_cli_answer(value) when is_binary(value), do: value
  defp format_cli_answer(value), do: inspect(value)
end
