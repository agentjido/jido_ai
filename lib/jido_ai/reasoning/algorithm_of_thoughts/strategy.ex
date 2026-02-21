defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy do
  @moduledoc """
  Algorithm-of-Thoughts (AoT) execution strategy for Jido agents.

  This strategy performs one-pass algorithmic reasoning with in-context search
  exemplars and extracts a structured AoT result.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Machine
  alias Jido.AI.Reasoning.Helpers
  alias ReqLLM.Context

  @type profile :: :short | :standard | :long
  @type search_style :: :dfs | :bfs

  @type config :: %{
          model: String.t(),
          profile: profile(),
          search_style: search_style(),
          temperature: float(),
          max_tokens: pos_integer(),
          examples: [String.t()],
          require_explicit_answer: boolean(),
          llm_timeout_ms: pos_integer() | nil
        }

  @default_model :fast

  @start :aot_start
  @llm_result :aot_llm_result
  @llm_partial :aot_llm_partial
  @request_error :aot_request_error

  @doc "Returns the action atom for starting AoT exploration."
  @spec start_action() :: :aot_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :aot_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling LLM partial deltas."
  @spec llm_partial_action() :: :aot_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request lifecycle rejections."
  @spec request_error_action() :: :aot_request_error
  def request_error_action, do: @request_error

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start an AoT reasoning session",
      name: "aot.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "aot.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "aot.llm_partial"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "aot.request_error"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.aot.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})
    status = map_status(state[:status])

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: state[:result],
      details: build_details(state)
    }
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)

    machine =
      Machine.new(
        profile: config.profile,
        search_style: config.search_style,
        temperature: config.temperature,
        max_tokens: config.max_tokens,
        examples: config.examples,
        require_explicit_answer: config.require_explicit_answer
      )

    state =
      machine
      |> Machine.to_map()
      |> Helpers.apply_to_state([Helpers.update_config(config)])

    {StratState.put(agent, state), []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    {agent, dirs_rev} =
      Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
        case process_instruction(acc_agent, instr, ctx) do
          {new_agent, new_dirs} ->
            {new_agent, Enum.reverse(new_dirs, acc_dirs)}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  @doc "Returns the last AoT result from strategy state."
  @spec get_result(Agent.t()) :: map() | nil
  def get_result(agent) do
    state = StratState.get(agent, %{})
    state[:result]
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params} = instruction, ctx) do
    normalized_action = normalize_action(action)
    state = StratState.get(agent, %{})
    config = state[:config] || %{}

    case normalized_action do
      @request_error ->
        process_request_error(agent, params)

      @llm_result ->
        apply_machine_update(agent, {:llm_result, params[:call_id], params[:result]}, config)

      _ ->
        case to_machine_msg(normalized_action, params) do
          msg when not is_nil(msg) ->
            apply_machine_update(agent, msg, config)

          _ ->
            Helpers.maybe_execute_action_instruction(agent, instruction, ctx)
        end
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{prompt: prompt} = params) when is_binary(prompt) do
    request_id =
      case Map.get(params, :request_id) do
        id when is_binary(id) -> id
        _ -> Machine.generate_call_id()
      end

    {:start, prompt, request_id}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type})
       when is_binary(call_id) and is_binary(delta) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp process_request_error(agent, %{request_id: request_id, reason: reason, message: message}) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
    {StratState.put(agent, new_state), []}
  end

  defp process_request_error(_, _), do: :noop

  defp apply_machine_update(agent, {:llm_result, call_id, _result}, _config) when not is_binary(call_id),
    do: {agent, []}

  defp apply_machine_update(agent, nil, _config), do: {agent, []}

  defp apply_machine_update(agent, msg, config) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)

    env = %{
      profile: config[:profile],
      search_style: config[:search_style],
      examples: config[:examples]
    }

    {machine, directives} = Machine.update(machine, msg, env)
    lifted_directives = lift_directives(directives, config)

    new_state =
      state
      |> Map.merge(Machine.to_map(machine))
      |> Helpers.apply_to_state([Helpers.update_config(config)])

    {StratState.put(agent, new_state), lifted_directives}
  end

  defp lift_directives(directives, config) do
    model =
      config
      |> Map.get(:model)
      |> Kernel.||(@default_model)
      |> resolve_model_spec()

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        [build_llm_directive(id, model, conversation, config)]

      {:request_error, request_id, reason, message} ->
        [
          Directive.EmitRequestError.new!(%{
            request_id: request_id,
            reason: reason,
            message: message
          })
        ]

      _ ->
        []
    end)
  end

  defp build_llm_directive(call_id, model, conversation, config) do
    attrs = %{
      id: call_id,
      model: model,
      context: convert_to_reqllm_context(conversation),
      temperature: config[:temperature] || 0.0,
      max_tokens: config[:max_tokens] || 2048
    }

    attrs =
      case config[:llm_timeout_ms] do
        timeout when is_integer(timeout) and timeout > 0 -> Map.put(attrs, :timeout, timeout)
        _ -> attrs
      end

    Directive.LLMStream.new!(attrs)
  end

  defp convert_to_reqllm_context(conversation) do
    case Context.normalize(conversation, validate: false) do
      {:ok, context} -> Context.to_list(context)
      _ -> conversation
    end
  end

  defp map_status(:completed), do: :success
  defp map_status(:error), do: :failure
  defp map_status(:idle), do: :idle
  defp map_status(_), do: :running

  defp build_details(state) do
    result = state[:result]

    %{
      phase: state[:status],
      profile: get_in(state, [:config, :profile]),
      search_style: get_in(state, [:config, :search_style]),
      require_explicit_answer: get_in(state, [:config, :require_explicit_answer]),
      usage: if(is_map(result), do: result[:usage], else: nil),
      termination: if(is_map(result), do: result[:termination], else: nil),
      diagnostics: if(is_map(result), do: result[:diagnostics], else: nil)
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(map) when map == %{}, do: true
  defp empty_value?(_), do: false

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    raw_model = Map.get(agent.state, :model, Keyword.get(opts, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      profile: Keyword.get(opts, :profile, :standard),
      search_style: Keyword.get(opts, :search_style, :dfs),
      temperature: normalize_temperature(Keyword.get(opts, :temperature, 0.0)),
      max_tokens: Keyword.get(opts, :max_tokens, 2048),
      examples: normalize_examples(Keyword.get(opts, :examples, [])),
      require_explicit_answer: Keyword.get(opts, :require_explicit_answer, true),
      llm_timeout_ms: Keyword.get(opts, :llm_timeout_ms)
    }
  end

  defp resolve_model_spec(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  defp resolve_model_spec(model) when is_binary(model), do: model
  defp resolve_model_spec(_), do: Jido.AI.resolve_model(@default_model)

  defp normalize_temperature(temp) when is_number(temp), do: temp * 1.0
  defp normalize_temperature(_), do: 0.0

  defp normalize_examples(examples) when is_list(examples) do
    examples
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_examples(_), do: []
end
