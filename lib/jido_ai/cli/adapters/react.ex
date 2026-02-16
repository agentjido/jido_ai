defmodule Jido.AI.CLI.Adapters.ReAct do
  @moduledoc """
  CLI adapter for `Jido.AI.Agent` modules (ReAct strategy implied).

  Handles the specifics of the agent lifecycle:
  - Uses `ask/2` to submit queries
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10
  @default_tools [
    Jido.Tools.Arithmetic.Add,
    Jido.Tools.Arithmetic.Subtract,
    Jido.Tools.Arithmetic.Multiply,
    Jido.Tools.Arithmetic.Divide,
    Jido.Tools.Weather
  ]

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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"ReAct#{suffix}"])

    tools = config[:tools] || @default_tools
    model = config[:model] || @default_model
    max_iterations = config[:max_iterations] || @default_max_iterations
    system_prompt = config[:system_prompt]

    contents =
      if system_prompt do
        quote do
          use Jido.AI.Agent,
            name: "cli_react_agent",
            description: "CLI ephemeral agent",
            tools: unquote(tools),
            model: unquote(model),
            max_iterations: unquote(max_iterations),
            system_prompt: unquote(system_prompt)
        end
      else
        quote do
          use Jido.AI.Agent,
            name: "cli_react_agent",
            description: "CLI ephemeral agent",
            tools: unquote(tools),
            model: unquote(model),
            max_iterations: unquote(max_iterations)
        end
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  # Private helpers

  defp poll_loop(pid, deadline, interval) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case Jido.AgentServer.status(pid) do
        {:ok, status} ->
          if status.snapshot.done? do
            # Prefer snapshot.result (general contract), fallback to raw_state.last_answer
            answer =
              case status.snapshot.result do
                nil -> Map.get(status.raw_state, :last_answer, "")
                "" -> Map.get(status.raw_state, :last_answer, "")
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
    strategy_state = Map.get(status.raw_state, :__strategy__, %{})
    details = Map.get(status.snapshot, :details, %{})

    %{
      status: status.snapshot.status,
      iterations: Map.get(strategy_state, :iteration, 0),
      usage: extract_usage(strategy_state, details),
      model: Map.get(details, :model)
    }
  end

  defp extract_usage(strategy_state, details) do
    # Try strategy state first (accumulated), then snapshot details
    usage = Map.get(strategy_state, :usage) || Map.get(details, :usage) || %{}

    if map_size(usage) > 0 do
      %{
        input_tokens: Map.get(usage, :input_tokens, 0),
        output_tokens: Map.get(usage, :output_tokens, 0),
        total_tokens:
          Map.get(usage, :total_tokens) ||
            Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0),
        cache_creation_input_tokens: Map.get(usage, :cache_creation_input_tokens),
        cache_read_input_tokens: Map.get(usage, :cache_read_input_tokens)
      }
    end
  end
end
