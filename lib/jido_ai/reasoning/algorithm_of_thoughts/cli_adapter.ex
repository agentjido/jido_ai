defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter do
  @moduledoc """
  CLI adapter for Algorithm-of-Thoughts-style agents.
  """

  @behaviour Jido.AI.CLI.Adapter

  @default_model "anthropic:claude-haiku-4-5"
  @default_profile :standard
  @default_search_style :dfs
  @default_temperature 0.0
  @default_max_tokens 2048

  @impl true
  def start_agent(jido_instance, agent_module, _config) do
    Jido.start_agent(jido_instance, agent_module)
  end

  @impl true
  def submit(pid, query, config) do
    config.agent_module.explore(pid, query)
  end

  @impl true
  def await(pid, timeout_ms, _config) do
    poll_loop(pid, System.monotonic_time(:millisecond) + timeout_ms, 100)
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
    module_name = Module.concat([JidoAi, EphemeralAgent, :"AoT#{suffix}"])

    model = config[:model] || @default_model
    profile = config[:profile] || @default_profile
    search_style = config[:search_style] || @default_search_style
    temperature = config[:temperature] || @default_temperature
    max_tokens = config[:max_tokens] || @default_max_tokens
    require_explicit_answer = Map.get(config, :require_explicit_answer, true)

    contents =
      quote do
        use Jido.AI.AoTAgent,
          name: "cli_aot_agent",
          description: "CLI ephemeral AoT agent",
          model: unquote(model),
          profile: unquote(profile),
          search_style: unquote(search_style),
          temperature: unquote(temperature),
          max_tokens: unquote(max_tokens),
          require_explicit_answer: unquote(require_explicit_answer)
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  defp poll_loop(pid, deadline, interval) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case Jido.AgentServer.status(pid) do
        {:ok, status} ->
          if status.snapshot.done? do
            result = status.snapshot.result

            {:ok,
             %{
               answer: extract_answer(result, status.raw_state),
               meta: extract_meta(status)
             }}
          else
            Process.sleep(interval)
            poll_loop(pid, deadline, interval)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_answer(%{answer: answer}, _raw_state) when is_binary(answer), do: answer
  defp extract_answer(result, _raw_state) when is_binary(result), do: result

  defp extract_answer(_result, raw_state) do
    case Map.get(raw_state, :last_result) do
      %{answer: answer} when is_binary(answer) -> answer
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp extract_meta(status) do
    details = status.snapshot.details || %{}
    result = status.snapshot.result

    %{
      status: status.snapshot.status,
      profile: Map.get(details, :profile),
      search_style: Map.get(details, :search_style),
      termination: if(is_map(result), do: Map.get(result, :termination), else: nil),
      usage: if(is_map(result), do: Map.get(result, :usage), else: nil),
      aot_result: if(is_map(result), do: result, else: nil)
    }
  end
end
