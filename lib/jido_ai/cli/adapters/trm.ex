defmodule Jido.AI.CLI.Adapters.TRM do
  @moduledoc """
  CLI adapter for TRM (Tiny-Recursive-Model) agents.

  Handles the specifics of TRM agent lifecycle:
  - Uses `reason/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    agent_module = config.agent_module
    agent_module.reason(pid, query)
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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"TRM#{suffix}"])

    model = config[:model] || @default_model
    max_supervision_steps = config[:max_supervision_steps] || @default_max_supervision_steps
    act_threshold = config[:act_threshold] || @default_act_threshold

    contents =
      quote do
        use Jido.AI.TRMAgent,
          name: "cli_trm_agent",
          description: "CLI ephemeral TRM agent",
          model: unquote(model),
          max_supervision_steps: unquote(max_supervision_steps),
          act_threshold: unquote(act_threshold)
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
      supervision_step: Map.get(details, :supervision_step, 0),
      best_score: Map.get(details, :best_score, 0.0),
      act_triggered: Map.get(details, :act_triggered, false)
    }
  end
end
