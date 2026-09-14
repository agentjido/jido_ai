defmodule Jido.AI.Reasoning.ReAct.CLIAdapter do
  @moduledoc """
  CLI adapter for `Jido.AI.Agent` modules (ReAct strategy implied).

  Handles the specifics of the agent lifecycle:
  - Uses `ask/2` to submit queries
  - Polls `strategy_snapshot.done?` for completion
  - Extracts result from `snapshot.result`
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model :fast
  @default_max_iterations 10
  @default_max_tokens 4_096
  @default_tools [
    Jido.AI.Tools.Arithmetic.Add,
    Jido.AI.Tools.Arithmetic.Subtract,
    Jido.AI.Tools.Arithmetic.Multiply,
    Jido.AI.Tools.Arithmetic.Divide
  ]

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    agent_module = config.agent_module

    ask_opts =
      []
      |> maybe_put_opt(:tool_context, config[:tool_context])
      |> maybe_put_opt(:req_http_options, config[:req_http_options])
      |> maybe_put_opt(:llm_opts, config[:llm_opts])

    if ask_opts == [] or not function_exported?(agent_module, :ask, 3) do
      agent_module.ask(pid, query)
    else
      agent_module.ask(pid, query, ask_opts)
    end
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
    max_tokens = config[:max_tokens] || @default_max_tokens
    system_prompt = config[:system_prompt]
    req_http_options = config[:req_http_options] || []
    llm_opts = config[:llm_opts] || []

    generation =
      llm_opts
      |> Jido.AI.Reasoning.ReAct.Config.normalize_option_names()
      |> Enum.into([])
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:req_http_options, req_http_options)

    Jido.AI.CLI.EphemeralAgent.create(module_name,
      method: :react,
      name: "cli_react_agent",
      description: "CLI ephemeral agent",
      model: model,
      tools: tools,
      instructions: system_prompt,
      generation: generation,
      max_iterations: max_iterations,
      max_model_calls: max_iterations
    )
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, _key, []), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # Private helpers

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
    details = Map.get(status.snapshot, :details, %{})

    %{
      status: status.snapshot.status,
      iterations: Map.get(details, :iteration, 0),
      usage: extract_usage(details),
      model: Map.get(details, :model)
    }
  end

  defp extract_usage(details) do
    usage = Map.get(details, :usage, %{})

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

  defp format_cli_answer(nil), do: ""
  defp format_cli_answer(value) when is_binary(value), do: value
  defp format_cli_answer(value), do: inspect(value)
end
