defmodule Jido.AI.Actions.Reasoning.RunStrategy do
  @moduledoc """
  Executes a reasoning strategy in an isolated runner agent context.

  This action is strategy-independent from the calling agent: it always starts
  a dedicated internal runner agent for the requested strategy.
  """

  use Jido.Action,
    name: "reasoning_run_strategy",
    description: "Run an isolated reasoning strategy by id",
    category: "ai",
    tags: ["reasoning", "strategies", "orchestration"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        strategy:
          Zoi.enum([:cod, :cot, :tot, :got, :trm, :aot, :adaptive],
            description: "Reasoning strategy identifier"
          ),
        prompt: Zoi.string(description: "Prompt to reason on"),
        model:
          Zoi.any(description: "Optional model alias (atom) or model spec (string)")
          |> Zoi.optional(),
        timeout:
          Zoi.integer(description: "Request timeout in milliseconds")
          |> Zoi.default(30_000)
          |> Zoi.optional(),
        options:
          Zoi.map(description: "Strategy-specific runtime options")
          |> Zoi.default(%{})
          |> Zoi.optional(),
        # CoT options
        system_prompt: Zoi.string(description: "Custom CoT system prompt") |> Zoi.optional(),
        llm_timeout_ms: Zoi.integer(description: "LLM timeout in milliseconds") |> Zoi.optional(),
        request_policy: Zoi.atom(description: "Request policy") |> Zoi.optional(),
        # ToT options
        branching_factor: Zoi.integer(description: "ToT branching factor") |> Zoi.optional(),
        max_depth: Zoi.integer(description: "ToT/GoT max depth") |> Zoi.optional(),
        traversal_strategy:
          Zoi.enum([:bfs, :dfs, :best_first], description: "ToT traversal strategy")
          |> Zoi.optional(),
        generation_prompt: Zoi.string(description: "Custom generation prompt") |> Zoi.optional(),
        evaluation_prompt: Zoi.string(description: "Custom ToT evaluation prompt") |> Zoi.optional(),
        # GoT options
        max_nodes: Zoi.integer(description: "GoT max nodes") |> Zoi.optional(),
        aggregation_strategy:
          Zoi.enum([:voting, :weighted, :synthesis], description: "GoT aggregation strategy")
          |> Zoi.optional(),
        connection_prompt: Zoi.string(description: "Custom GoT connection prompt") |> Zoi.optional(),
        aggregation_prompt: Zoi.string(description: "Custom GoT aggregation prompt") |> Zoi.optional(),
        # TRM options
        max_supervision_steps: Zoi.integer(description: "TRM max supervision steps") |> Zoi.optional(),
        act_threshold: Zoi.float(description: "TRM ACT threshold") |> Zoi.optional(),
        # AoT options
        profile:
          Zoi.enum([:short, :standard, :long], description: "AoT in-context profile")
          |> Zoi.optional(),
        search_style:
          Zoi.enum([:dfs, :bfs], description: "AoT search style preference")
          |> Zoi.optional(),
        temperature: Zoi.float(description: "AoT temperature override") |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "AoT max generation tokens") |> Zoi.optional(),
        examples:
          Zoi.list(Zoi.string(description: "AoT algorithmic in-context example"), description: "AoT examples")
          |> Zoi.optional(),
        require_explicit_answer:
          Zoi.boolean(description: "Require an explicit `answer:` line for AoT success")
          |> Zoi.optional(),
        # Adaptive options
        default_strategy:
          Zoi.enum([:cod, :cot, :react, :tot, :got, :trm, :aot], description: "Adaptive default strategy")
          |> Zoi.optional(),
        available_strategies:
          Zoi.list(
            Zoi.enum([:cod, :cot, :react, :tot, :got, :trm, :aot], description: "Adaptive strategy id"),
            description: "Adaptive available strategies"
          )
          |> Zoi.optional(),
        complexity_thresholds:
          Zoi.map(description: "Adaptive complexity thresholds")
          |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido

  alias Jido.AI.Actions.Reasoning.Runner.{
    AdaptiveAgent,
    AlgorithmOfThoughtsAgent,
    ChainOfDraftAgent,
    ChainOfThoughtAgent,
    GraphOfThoughtsAgent,
    TreeOfThoughtsAgent,
    TRMAgent
  }

  @strategy_runners %{
    cod: ChainOfDraftAgent,
    cot: ChainOfThoughtAgent,
    tot: TreeOfThoughtsAgent,
    got: GraphOfThoughtsAgent,
    trm: TRMAgent,
    aot: AlgorithmOfThoughtsAgent,
    adaptive: AdaptiveAgent
  }

  @strategy_state_keys %{
    cod: [:model, :system_prompt, :llm_timeout_ms, :request_policy],
    cot: [:model, :system_prompt, :llm_timeout_ms, :request_policy],
    tot: [:model, :branching_factor, :max_depth, :traversal_strategy, :generation_prompt, :evaluation_prompt],
    got: [
      :model,
      :max_nodes,
      :max_depth,
      :aggregation_strategy,
      :generation_prompt,
      :connection_prompt,
      :aggregation_prompt
    ],
    trm: [:model, :max_supervision_steps, :act_threshold],
    aot: [
      :model,
      :profile,
      :search_style,
      :temperature,
      :max_tokens,
      :examples,
      :require_explicit_answer,
      :llm_timeout_ms
    ],
    adaptive: [:model, :default_strategy, :available_strategies, :complexity_thresholds]
  }
  @runner_jido Jido.AI.InternalReasoningRunner

  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)
    strategy = params[:strategy]
    runner = Map.get(@strategy_runners, strategy)

    with true <- is_binary(params[:prompt]) and params[:prompt] != "",
         true <- not is_nil(runner),
         {:ok, result} <- run_in_runner(runner, strategy, params) do
      {:ok, result}
    else
      false ->
        {:error, :invalid_strategy_request}

      {:error, _reason} = error ->
        error
    end
  end

  defp run_in_runner(runner, strategy, params) do
    agent = build_runner_agent(runner, strategy, params)
    timeout = params[:timeout] || 30_000

    with :ok <- ensure_runner_runtime(),
         {:ok, pid} <-
           Jido.AgentServer.start_link(jido: @runner_jido, agent: agent, agent_module: runner) do
      try do
        run_result = invoke_runner(runner, strategy, pid, params[:prompt], timeout)
        snapshot = fetch_snapshot(runner, pid)
        normalize_runner_result(run_result, strategy, timeout, params, snapshot)
      after
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end
    end
  end

  defp ensure_runner_runtime do
    case Jido.start(name: @runner_jido) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)
    strategy = params[:strategy]
    strategy_defaults = strategy_plugin_defaults(context, strategy)

    model_default =
      first_present([
        context[:default_model],
        Map.get(strategy_defaults, :default_model)
      ])

    timeout_default =
      first_present([
        context[:timeout],
        Map.get(strategy_defaults, :timeout)
      ])

    options_default =
      first_present([
        context[:options],
        Map.get(strategy_defaults, :options)
      ]) || %{}

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:timeout, timeout_default, provided)
    |> merge_options_default(options_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp build_runner_agent(runner, strategy, params) do
    state =
      @strategy_state_keys
      |> Map.get(strategy, [])
      |> Enum.reduce(%{}, fn key, acc ->
        case strategy_option(params, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    runner.new(state: state)
  end

  defp strategy_option(params, key) do
    top_level = Map.get(params, key, Map.get(params, Atom.to_string(key)))

    options_level =
      params
      |> Map.get(:options, %{})
      |> then(fn options -> Map.get(options, key, Map.get(options, Atom.to_string(key))) end)

    first_present([top_level, options_level])
  end

  defp invoke_runner(runner, :cod, pid, prompt, timeout), do: runner.draft_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :cot, pid, prompt, timeout), do: runner.think_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :tot, pid, prompt, timeout), do: runner.explore_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :got, pid, prompt, timeout), do: runner.explore_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :trm, pid, prompt, timeout), do: runner.reason_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :aot, pid, prompt, timeout), do: runner.explore_sync(pid, prompt, timeout: timeout)
  defp invoke_runner(runner, :adaptive, pid, prompt, timeout), do: runner.ask_sync(pid, prompt, timeout: timeout)

  defp fetch_snapshot(runner, pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, state} -> runner.strategy_snapshot(state.agent)
      _ -> nil
    end
  end

  defp normalize_runner_result({:ok, output}, strategy, timeout, params, snapshot) do
    {:ok,
     %{
       strategy: strategy,
       status: snapshot_status(snapshot, :success),
       output: output,
       usage: extract_usage(snapshot),
       diagnostics: diagnostics(timeout, params, snapshot, nil)
     }}
  end

  defp normalize_runner_result({:error, reason}, strategy, timeout, params, snapshot) do
    case maybe_recover_success(snapshot) do
      {:ok, output} ->
        {:ok,
         %{
           strategy: strategy,
           status: snapshot_status(snapshot, :success),
           output: output,
           usage: extract_usage(snapshot),
           diagnostics:
             diagnostics(timeout, params, snapshot, nil)
             |> Map.put(:recovered_error, Helpers.sanitize_error(reason))
         }}

      :error ->
        {:error,
         %{
           strategy: strategy,
           status: snapshot_status(snapshot, :failure),
           output: snapshot_output(snapshot),
           usage: extract_usage(snapshot),
           diagnostics: diagnostics(timeout, params, snapshot, Helpers.sanitize_error(reason))
         }}
    end
  end

  defp normalize_runner_result(other, strategy, timeout, params, snapshot) do
    {:error,
     %{
       strategy: strategy,
       status: snapshot_status(snapshot, :failure),
       output: nil,
       usage: extract_usage(snapshot),
       diagnostics: diagnostics(timeout, params, snapshot, inspect(other))
     }}
  end

  defp snapshot_status(%{status: status}, _fallback) when not is_nil(status), do: status
  defp snapshot_status(_snapshot, fallback), do: fallback

  defp extract_usage(%{details: details}) when is_map(details) do
    Map.get(details, :usage, Map.get(details, "usage", %{}))
  end

  defp extract_usage(_), do: %{}

  defp diagnostics(timeout, params, snapshot, error) do
    %{
      timeout: timeout,
      options: Map.get(params, :options, %{}),
      snapshot_status: snapshot_status(snapshot, :unknown),
      snapshot_done: snapshot_done?(snapshot),
      snapshot_details: snapshot_details(snapshot),
      error: error
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
    |> Map.new()
  end

  defp snapshot_done?(%{done?: done?}), do: done?
  defp snapshot_done?(_), do: nil

  defp snapshot_details(%{details: details}) when is_map(details), do: details
  defp snapshot_details(_), do: %{}

  defp maybe_recover_success(snapshot) do
    output = snapshot_output(snapshot)

    if snapshot_done?(snapshot) == true and snapshot_status(snapshot, :unknown) == :success and
         not is_nil(output) do
      {:ok, output}
    else
      :error
    end
  end

  defp snapshot_output(%{result: result}) when not is_nil(result), do: result

  defp snapshot_output(%{details: details}) when is_map(details) do
    first_present([
      Map.get(details, :result),
      Map.get(details, "result"),
      Map.get(details, :best_answer),
      Map.get(details, "best_answer"),
      Map.get(details, :final_answer),
      Map.get(details, "final_answer"),
      Map.get(details, :current_answer),
      Map.get(details, "current_answer"),
      Map.get(details, :streaming_text),
      Map.get(details, "streaming_text"),
      Map.get(details, :conclusion),
      Map.get(details, "conclusion")
    ])
  end

  defp snapshot_output(_), do: nil

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp merge_options_default(params, defaults, _provided) when defaults == %{}, do: params

  defp merge_options_default(params, defaults, provided) do
    current = Map.get(params, :options, %{})

    merged =
      cond do
        provided == :unknown and (current == %{} or is_nil(current)) ->
          defaults

        provided == :unknown ->
          Map.merge(defaults, current)

        provided_param?(provided, :options) ->
          Map.merge(defaults, current)

        true ->
          defaults
      end

    Map.put(params, :options, merged)
  end

  defp strategy_plugin_defaults(context, strategy) do
    key = strategy_state_key(strategy)

    first_present([
      get_in(context, [:plugin_state, key]),
      get_in(context, [:state, key]),
      get_in(context, [:agent, :state, key])
    ]) || %{}
  end

  defp strategy_state_key(:cot), do: :reasoning_cot
  defp strategy_state_key(:cod), do: :reasoning_cod
  defp strategy_state_key(:tot), do: :reasoning_tot
  defp strategy_state_key(:got), do: :reasoning_got
  defp strategy_state_key(:trm), do: :reasoning_trm
  defp strategy_state_key(:aot), do: :reasoning_aot
  defp strategy_state_key(:adaptive), do: :reasoning_adaptive
  defp strategy_state_key(_), do: nil

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
