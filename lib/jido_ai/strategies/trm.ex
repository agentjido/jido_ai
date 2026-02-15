# NOTE: Module is in `Strategies` namespace (plural) to match other strategies
# in this codebase (e.g., Jido.AI.Strategies.Adaptive, Jido.AI.Strategies.ReAct).
defmodule Jido.AI.Strategies.TRM do
  @moduledoc """
  TRM (Tiny-Recursive-Model) execution strategy for Jido agents.

  This strategy implements recursive reasoning by iteratively improving answers
  through a reason-supervise-improve cycle. Each iteration:
  1. **Reasoning**: Generate insights about the current answer
  2. **Supervision**: Evaluate the answer and provide feedback
  3. **Improvement**: Apply feedback to generate a better answer

  ## Overview

  TRM uses a tiny network applied recursively to iteratively improve answers,
  achieving remarkable parameter efficiency while outperforming larger models
  on complex reasoning tasks. Key features:

  - Recursive reasoning loop with iterative answer improvement
  - Deep supervision with multiple feedback steps
  - Adaptive Computational Time (ACT) for early stopping
  - Latent state management across recursion steps

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.TRM.Machine`) for all state
  transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_trm_agent",
        strategy: {
          Jido.AI.Strategies.TRM,
          model: "anthropic:claude-sonnet-4-20250514",
          max_supervision_steps: 5,
          act_threshold: 0.9
        }

  ### Options

  - `:model` (optional) - Model identifier, defaults to "anthropic:claude-haiku-4-5"
  - `:max_supervision_steps` (optional) - Maximum iterations before termination, defaults to 5
  - `:act_threshold` (optional) - Confidence threshold for early stopping, defaults to 0.9

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"ai.trm.query"` → `:trm_start`
  - `"ai.llm.response"` → `:trm_llm_result`
  - `"ai.llm.delta"` → `:trm_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with TRM-specific structure.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.TRM.Machine
  alias Jido.AI.TRM.Reasoning
  alias Jido.AI.TRM.Supervision
  alias ReqLLM.Context

  @type config :: %{
          model: String.t(),
          max_supervision_steps: pos_integer(),
          act_threshold: float()
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  @start :trm_start
  @llm_result :trm_llm_result
  @llm_partial :trm_llm_partial
  @request_error :trm_request_error

  @doc "Returns the action atom for starting TRM reasoning."
  @spec start_action() :: :trm_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :trm_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :trm_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :trm_request_error
  def request_error_action, do: @request_error

  # Maximum prompt length to prevent resource exhaustion (enforced in sanitization)
  # Length validation is handled by Jido.AI.TRM.Helpers.sanitize_user_input/2

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start TRM recursive reasoning with a prompt",
      name: "trm.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response for any TRM phase",
      name: "trm.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "trm.llm_partial"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "trm.request_error"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.trm.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      # Usage report is emitted for observability but doesn't need processing
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

  defp map_status(:completed), do: :success
  defp map_status(:error), do: :failure
  defp map_status(:idle), do: :idle
  defp map_status(_), do: :running

  defp build_details(state) do
    %{
      phase: state[:status],
      supervision_step: state[:supervision_step],
      max_supervision_steps: state[:max_supervision_steps],
      act_threshold: state[:act_threshold],
      act_triggered: state[:act_triggered],
      best_score: state[:best_score],
      answer_count: length(state[:answer_history] || []),
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at])
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(map) when map == %{}, do: true
  defp empty_value?(0), do: false
  defp empty_value?(false), do: false
  defp empty_value?(_), do: false

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)

    machine =
      Machine.new(
        max_supervision_steps: config.max_supervision_steps,
        act_threshold: config.act_threshold
      )

    state =
      machine
      |> Machine.to_map()
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    {agent, dirs_rev} =
      Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
        case process_instruction(acc_agent, instr) do
          {new_agent, new_dirs} ->
            {new_agent, Enum.reverse(new_dirs, acc_dirs)}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  # Public Helpers

  @doc """
  Gets the answer history from the agent's TRM state.
  """
  @spec get_answer_history(Agent.t()) :: [String.t()]
  def get_answer_history(agent) do
    state = StratState.get(agent, %{})
    state[:answer_history] || []
  end

  @doc """
  Gets the current answer from the agent's TRM state.
  """
  @spec get_current_answer(Agent.t()) :: String.t() | nil
  def get_current_answer(agent) do
    state = StratState.get(agent, %{})
    state[:current_answer]
  end

  @doc """
  Gets the current confidence score from the agent's TRM state.
  """
  @spec get_confidence(Agent.t()) :: float()
  def get_confidence(agent) do
    state = StratState.get(agent, %{})
    latent_state = state[:latent_state] || %{}
    latent_state[:confidence_score] || 0.0
  end

  @doc """
  Gets the current supervision step from the agent's TRM state.
  """
  @spec get_supervision_step(Agent.t()) :: non_neg_integer()
  def get_supervision_step(agent) do
    state = StratState.get(agent, %{})
    state[:supervision_step] || 0
  end

  @doc """
  Gets the best answer found so far.
  """
  @spec get_best_answer(Agent.t()) :: String.t() | nil
  def get_best_answer(agent) do
    state = StratState.get(agent, %{})
    state[:best_answer]
  end

  @doc """
  Gets the best score achieved.
  """
  @spec get_best_score(Agent.t()) :: float()
  def get_best_score(agent) do
    state = StratState.get(agent, %{})
    state[:best_score] || 0.0
  end

  # Private Helpers

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    # Resolve model
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      max_supervision_steps: Keyword.get(opts, :max_supervision_steps, @default_max_supervision_steps),
      act_threshold: Keyword.get(opts, :act_threshold, @default_act_threshold)
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    normalized_action = normalize_action(action)

    case normalized_action do
      @request_error ->
        process_request_error(agent, params)

      _ ->
        case to_machine_msg(normalized_action, params) do
          msg when not is_nil(msg) ->
            state = StratState.get(agent, %{})
            config = state[:config]
            machine = Machine.from_map(state)

            {machine, directives} = Machine.update(machine, msg, %{})

            new_state =
              machine
              |> Machine.to_map()
              |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

            agent = StratState.put(agent, new_state)
            {agent, lift_directives(directives, config)}

          _ ->
            :noop
        end
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, params) do
    prompt = Map.get(params, :prompt) || Map.get(params, "prompt")
    request_id = Map.get(params, :request_id) || Map.get(params, "request_id") || Machine.generate_call_id()
    {:start, prompt, request_id}
  end

  defp to_machine_msg(@llm_result, params) do
    call_id = Map.get(params, :call_id) || Map.get(params, "call_id")
    result = Map.get(params, :result) || Map.get(params, "result")
    phase = Map.get(params, :phase) || Map.get(params, "phase") || :reasoning

    # Convert to appropriate machine message based on phase
    case phase do
      :reasoning -> {:reasoning_result, call_id, result}
      :supervising -> {:supervision_result, call_id, result}
      :improving -> {:improvement_result, call_id, result}
      _ -> {:reasoning_result, call_id, result}
    end
  end

  defp to_machine_msg(@llm_partial, params) do
    call_id = Map.get(params, :call_id) || Map.get(params, "call_id")
    delta = Map.get(params, :delta) || Map.get(params, "delta")
    chunk_type = Map.get(params, :chunk_type) || Map.get(params, "chunk_type") || :content
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp process_request_error(agent, params) do
    request_id = Map.get(params, :request_id) || Map.get(params, "request_id")
    reason = Map.get(params, :reason) || Map.get(params, "reason")
    message = Map.get(params, :message) || Map.get(params, "message")

    if is_binary(request_id) do
      state = StratState.get(agent, %{})
      new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
      {StratState.put(agent, new_state), []}
    else
      :noop
    end
  end

  # NOTE: The directive building functions below (build_*_directive and
  # convert_to_reqllm_context) share patterns with other strategies like ReAct.
  # A future refactoring could extract these into a shared Jido.AI.Strategy.Helpers
  # module to reduce duplication across strategies.

  defp lift_directives(directives, config) do
    %{model: model} = config

    Enum.flat_map(directives, fn
      {:reason, id, context} ->
        [build_reasoning_directive(id, context, model, config)]

      {:supervise, id, context} ->
        [build_supervision_directive(id, context, model, config)]

      {:improve, id, context} ->
        [build_improvement_directive(id, context, model, config)]

      # Issue #9 fix: Handle request rejection when agent is busy
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

  defp build_reasoning_directive(id, context, model, _config) do
    # Use Reasoning module for structured prompt building
    reasoning_context = %{
      question: context[:question],
      current_answer: context[:current_answer],
      latent_state: context[:latent_state]
    }

    {system, user} = Reasoning.build_reasoning_prompt(reasoning_context)

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: [],
      metadata: %{phase: :reasoning}
    })
  end

  defp build_supervision_directive(id, context, model, _config) do
    # Use Supervision module for structured prompt building
    # Include previous_feedback from Machine for iterative improvement context
    supervision_context = %{
      question: context[:question],
      answer: context[:current_answer],
      step: context[:step],
      previous_feedback: context[:previous_feedback]
    }

    {system, user} = Supervision.build_supervision_prompt(supervision_context)

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: [],
      metadata: %{phase: :supervising}
    })
  end

  defp build_improvement_directive(id, context, model, _config) do
    # Use Supervision module for improvement prompt building
    # Use parsed feedback if available, otherwise parse the raw feedback
    parsed_feedback =
      context[:parsed_feedback] ||
        Supervision.parse_supervision_result(context[:feedback] || "")

    {system, user} =
      Supervision.build_improvement_prompt(
        context[:question],
        context[:current_answer],
        parsed_feedback
      )

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: [],
      metadata: %{phase: :improving}
    })
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  # Default Prompts - delegate to TRM support modules for consistency

  @doc """
  Returns the default system prompt for reasoning phase.

  This is provided for reference - prompts are managed internally by
  the Reasoning module. See `Jido.AI.TRM.Reasoning` for details.
  """
  @spec default_reasoning_prompt() :: String.t()
  def default_reasoning_prompt do
    Reasoning.default_reasoning_system_prompt()
  end

  @doc """
  Returns the default system prompt for supervision phase.

  This is provided for reference - prompts are managed internally by
  the Supervision module. See `Jido.AI.TRM.Supervision` for details.
  """
  @spec default_supervision_prompt() :: String.t()
  def default_supervision_prompt do
    Supervision.default_supervision_system_prompt()
  end

  @doc """
  Returns the default system prompt for improvement phase.

  This is provided for reference - prompts are managed internally by
  the Supervision module. See `Jido.AI.TRM.Supervision` for details.
  """
  @spec default_improvement_prompt() :: String.t()
  def default_improvement_prompt do
    Supervision.default_improvement_system_prompt()
  end
end
