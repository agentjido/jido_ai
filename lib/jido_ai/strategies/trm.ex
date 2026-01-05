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
  - `:reasoning_prompt` (optional) - Custom prompt for reasoning phase
  - `:supervision_prompt` (optional) - Custom prompt for supervision phase
  - `:improvement_prompt` (optional) - Custom prompt for improvement phase

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"trm.query"` → `:trm_start`
  - `"reqllm.result"` → `:trm_llm_result`
  - `"reqllm.partial"` → `:trm_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with TRM-specific structure.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Config
  alias Jido.AI.Directive
  alias Jido.AI.TRM.Machine
  alias Jido.AI.TRM.Reasoning
  alias Jido.AI.TRM.Supervision
  alias ReqLLM.Context

  @type config :: %{
          model: String.t(),
          max_supervision_steps: pos_integer(),
          act_threshold: float(),
          reasoning_prompt: String.t(),
          supervision_prompt: String.t(),
          improvement_prompt: String.t()
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  @start :trm_start
  @llm_result :trm_llm_result
  @llm_partial :trm_llm_partial

  @doc "Returns the action atom for starting TRM reasoning."
  @spec start_action() :: :trm_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :trm_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :trm_llm_partial
  def llm_partial_action, do: @llm_partial

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{question: Zoi.string()}),
      doc: "Start TRM recursive reasoning with a question",
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
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"trm.query", {:strategy_cmd, @start}},
      {"reqllm.result", {:strategy_cmd, @llm_result}},
      {"reqllm.partial", {:strategy_cmd, @llm_partial}}
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
      |> Map.put(:config, config)

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
      max_supervision_steps:
        Keyword.get(opts, :max_supervision_steps, @default_max_supervision_steps),
      act_threshold: Keyword.get(opts, :act_threshold, @default_act_threshold),
      reasoning_prompt: Keyword.get(opts, :reasoning_prompt, default_reasoning_prompt()),
      supervision_prompt: Keyword.get(opts, :supervision_prompt, default_supervision_prompt()),
      improvement_prompt: Keyword.get(opts, :improvement_prompt, default_improvement_prompt())
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Config.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    case to_machine_msg(normalize_action(action), params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        {machine, directives} = Machine.update(machine, msg, %{})

        new_state =
          machine
          |> Machine.to_map()
          |> Map.put(:config, config)

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config)}

      _ ->
        :noop
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, params) do
    question = Map.get(params, :question) || Map.get(params, "question")
    call_id = Machine.generate_call_id()
    {:start, question, call_id}
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

  defp lift_directives(directives, config) do
    %{model: model} = config

    Enum.flat_map(directives, fn
      {:reason, id, context} ->
        [build_reasoning_directive(id, context, model, config)]

      {:supervise, id, context} ->
        [build_supervision_directive(id, context, model, config)]

      {:improve, id, context} ->
        [build_improvement_directive(id, context, model, config)]

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

    Directive.ReqLLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: [],
      metadata: %{phase: :reasoning}
    })
  end

  defp build_supervision_directive(id, context, model, _config) do
    # Use Supervision module for structured prompt building
    supervision_context = %{
      question: context[:question],
      answer: context[:current_answer],
      step: context[:step],
      previous_feedback: nil
    }

    {system, user} = Supervision.build_supervision_prompt(supervision_context)

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.ReqLLMStream.new!(%{
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

    {system, user} = Supervision.build_improvement_prompt(
      context[:question],
      context[:current_answer],
      parsed_feedback
    )

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.ReqLLMStream.new!(%{
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
  Delegates to `Jido.AI.TRM.Reasoning.default_reasoning_system_prompt/0`.
  """
  @spec default_reasoning_prompt() :: String.t()
  def default_reasoning_prompt do
    Reasoning.default_reasoning_system_prompt()
  end

  @doc """
  Returns the default system prompt for supervision phase.
  Delegates to `Jido.AI.TRM.Supervision.default_supervision_system_prompt/0`.
  """
  @spec default_supervision_prompt() :: String.t()
  def default_supervision_prompt do
    Supervision.default_supervision_system_prompt()
  end

  @doc """
  Returns the default system prompt for improvement phase.
  Delegates to `Jido.AI.TRM.Supervision.default_improvement_system_prompt/0`.
  """
  @spec default_improvement_prompt() :: String.t()
  def default_improvement_prompt do
    Supervision.default_improvement_system_prompt()
  end
end
