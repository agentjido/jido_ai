defmodule Jido.AI.CLI.Adapters.CoT do
  @moduledoc """
  CLI adapter for Chain-of-Thought-style agents.

  Handles the specifics of CoT agent lifecycle:
  - Uses `think/2` to submit prompts
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter
  alias Jido.AI.CLI.Adapters.Polling

  @default_model "anthropic:claude-haiku-4-5"

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    agent_module = config.agent_module
    agent_module.think(pid, query)
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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"CoT#{suffix}"])

    model = config[:model] || @default_model
    system_prompt = config[:system_prompt]

    contents =
      if system_prompt do
        quote do
          use Jido.AI.CoTAgent,
            name: "cli_cot_agent",
            description: "CLI ephemeral CoT agent",
            model: unquote(model),
            system_prompt: unquote(system_prompt)
        end
      else
        quote do
          use Jido.AI.CoTAgent,
            name: "cli_cot_agent",
            description: "CLI ephemeral CoT agent",
            model: unquote(model)
        end
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  defp extract_meta(status) do
    details = status.snapshot.details || %{}

    %{
      status: status.snapshot.status,
      steps_count: Map.get(details, :steps_count, 0),
      phase: Map.get(details, :phase),
      duration_ms: Map.get(details, :duration_ms)
    }
  end
end
