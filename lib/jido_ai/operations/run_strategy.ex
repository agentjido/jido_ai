defmodule Jido.AI.Actions.Reasoning.RunStrategy do
  @moduledoc """
  Runs one reasoning method in an isolated v3 Agent and Session.

  The caller owns the linked Agent. The same validated profile and core Flow
  serve direct Actions and declared AI Agents. Completion stops the private
  Agent; no v2 Strategy or private Directive executor is used.
  """

  use Jido.Action,
    name: "reasoning_run_strategy",
    description: "Run an isolated reasoning strategy by id",
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
        evaluation_prompt:
          Zoi.string(description: "Custom ToT evaluation prompt") |> Zoi.optional(),
        # GoT options
        max_nodes: Zoi.integer(description: "GoT max nodes") |> Zoi.optional(),
        aggregation_strategy:
          Zoi.enum([:voting, :weighted, :synthesis], description: "GoT aggregation strategy")
          |> Zoi.optional(),
        connection_prompt:
          Zoi.string(description: "Custom GoT connection prompt") |> Zoi.optional(),
        aggregation_prompt:
          Zoi.string(description: "Custom GoT aggregation prompt") |> Zoi.optional(),
        # TRM options
        max_supervision_steps:
          Zoi.integer(description: "TRM max supervision steps") |> Zoi.optional(),
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
          Zoi.list(Zoi.string(description: "AoT algorithmic in-context example"),
            description: "AoT examples"
          )
          |> Zoi.optional(),
        require_explicit_answer:
          Zoi.boolean(description: "Require an explicit `answer:` line for AoT success")
          |> Zoi.optional(),
        # Adaptive options
        default_strategy:
          Zoi.enum([:cod, :cot, :react, :tot, :got, :trm, :aot],
            description: "Adaptive default strategy"
          )
          |> Zoi.optional(),
        available_strategies:
          Zoi.list(
            Zoi.enum([:cod, :cot, :react, :tot, :got, :trm, :aot],
              description: "Adaptive strategy id"
            ),
            description: "Adaptive available strategies"
          )
          |> Zoi.optional(),
        complexity_thresholds:
          Zoi.map(description: "Adaptive complexity thresholds")
          |> Zoi.optional()
      })

  @doc "Legacy catalog category."
  def category, do: "ai"
  @doc "Legacy catalog tags."
  def tags, do: ["reasoning", "strategies", "orchestration"]
  @doc "Legacy Action contract version."
  def vsn, do: "1.0.0"

  alias Jido.AI.{Authoring, Profile, Request, Session}
  alias Jido.AgentServer, as: Server

  @methods %{
    cod: :chain_of_draft,
    cot: :chain_of_thought,
    tot: :tree_of_thoughts,
    got: :graph_of_thoughts,
    trm: :trm,
    aot: :algorithm_of_thoughts,
    adaptive: :adaptive
  }

  @strategy_state_keys %{
    cod: [:model, :system_prompt, :llm_timeout_ms, :request_policy],
    cot: [:model, :system_prompt, :llm_timeout_ms, :request_policy],
    tot: [
      :model,
      :branching_factor,
      :max_depth,
      :traversal_strategy,
      :generation_prompt,
      :evaluation_prompt
    ],
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
  @impl Jido.Action
  def run(params, context) do
    context = normalize_context(context)
    params = apply_context_defaults(params, context)
    strategy = params[:strategy]

    if is_binary(params[:prompt]) and params[:prompt] != "" and Map.has_key?(@methods, strategy) do
      with {:ok, definition} <- runner_definition(strategy, params),
           {:ok, server} <-
             Server.start_link([agent: definition] ++ Map.to_list(Map.take(context, [:jido]))) do
        try do
          run_request(server, strategy, params, normalize_context(context))
        after
          stop_runner(server)
        end
      end
    else
      {:error, :invalid_strategy_request}
    end
  end

  defp run_request(server, strategy, params, context) do
    timeout = params[:timeout] || 30_000

    with :ok <- Server.await_ready(server, timeout),
         {:ok, handle} <-
           Request.create_and_send(server, params.prompt,
             signal_type: "reasoning.run",
             source: "/ai/reasoning/action",
             context:
               Map.merge(Session.caller_context(context), Map.take(context, [:jido_ai_quota]))
           ) do
      result = Request.await(handle, timeout: timeout)
      if result == {:error, :timeout}, do: Session.cancel(handle, reason: :timeout)
      snapshot = fetch_snapshot(server, handle.id)
      normalize_runner_result(result, strategy, timeout, params, snapshot)
    end
  end

  defp stop_runner(server) do
    if Process.alive?(server), do: Server.stop(server, :normal)
  catch
    :exit, _reason -> :ok
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

  defp runner_definition(strategy, params) do
    method = @methods[strategy]

    options =
      Map.new(@strategy_state_keys[strategy], fn key -> {key, strategy_option(params, key)} end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    timeout = params[:timeout] || 30_000

    generation =
      options
      |> Map.take([:temperature, :max_tokens])
      |> Enum.to_list()
      |> then(fn generation ->
        case options[:llm_timeout_ms] do
          nil -> generation
          value -> Keyword.put(generation, :receive_timeout, value)
        end
      end)

    method_options =
      Map.drop(options, [
        :model,
        :system_prompt,
        :llm_timeout_ms,
        :request_policy,
        :temperature,
        :max_tokens,
        :default_strategy
      ])

    profile = %{
      id: :assistant,
      instructions: options[:system_prompt],
      models: %{answer: %{model: Map.get(options, :model, :fast), generation: generation}},
      reasoning: %{method: method, model: :answer, options: method_options},
      controls: %{
        timeout: timeout,
        max_iterations: :method_default,
        max_model_calls: :method_default,
        max_tool_calls: :method_default
      },
      requests: %{
        mode: :session,
        streaming: true,
        on_busy: Map.get(options, :request_policy, :reject)
      },
      result: %{schema: nil, into: :result}
    }

    base = %{
      name: "jido_ai_internal_reasoning_runner",
      plugins: Jido.AI.PluginStack.default_plugins(),
      schema: Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)}),
      routes: [{"reasoning.run", Authoring.ai(:assistant)}]
    }

    with {:ok, profile} <- Profile.new(profile), do: Authoring.lower(base, [profile])
  end

  defp strategy_option(params, key) do
    top_level = Map.get(params, key, Map.get(params, Atom.to_string(key)))
    options = Map.get(params, :options, %{}) || %{}
    options_level = Map.get(options, key, Map.get(options, Atom.to_string(key)))
    first_present([top_level, options_level])
  end

  defp fetch_snapshot(server, id) do
    with {:ok, records} <- Server.plugin_state(server, Jido.AI.Session.Plugin),
         record when is_map(record) <- records[id] do
      status =
        case record.status do
          :completed -> :success
          :failed -> :failure
          :pending -> :running
        end

      failure =
        case record.error do
          {:failed, _, details} when is_map(details) -> details
          _ -> %{}
        end

      details =
        record.meta
        |> Map.merge(Map.get(record.meta, :reasoning, %{}))
        |> Map.merge(failure)

      result =
        cond do
          record.result != nil -> record.result
          is_map_key(failure, :tree) or is_map_key(failure, :found_solution?) -> failure
          true -> failure[:result]
        end

      %{status: status, done?: record.status != :pending, result: result, details: details}
    else
      _ -> nil
    end
  catch
    :exit, _reason -> nil
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
             |> Map.put(:recovered_error, Jido.AI.Error.Sanitize.sanitize_error_message(reason))
         }}

      :error ->
        {:error,
         %{
           strategy: strategy,
           status: snapshot_status(snapshot, :failure),
           output: snapshot_output(snapshot),
           usage: extract_usage(snapshot),
           diagnostics:
             diagnostics(
               timeout,
               params,
               snapshot,
               Jido.AI.Error.Sanitize.sanitize_error_message(reason)
             )
         }}
    end
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

  defp snapshot_output(%{result: result}), do: result
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
      agent_state_default(context, key)
    ]) || %{}
  end

  defp agent_state_default(%{agent: %{state: state}}, key) when is_map(state),
    do: Map.get(state, key)

  defp agent_state_default(_, _), do: nil

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
