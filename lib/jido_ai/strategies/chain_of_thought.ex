defmodule Jido.AI.Strategies.ChainOfThought do
  @moduledoc """
  Chain-of-Thought (CoT) execution strategy for Jido agents.

  This strategy implements step-by-step reasoning by prompting the LLM to break
  down problems into intermediate steps before providing a final answer.

  ## Overview

  Chain-of-Thought prompting has been shown to significantly improve LLM
  performance on multi-step reasoning tasks like:
  - Mathematical word problems
  - Logical reasoning
  - Common sense reasoning
  - Multi-hop question answering

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.ChainOfThought.Machine`) for
  all state transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_cot_agent",
        strategy: {
          Jido.AI.Strategies.ChainOfThought,
          system_prompt: "Think step by step...",
          model: "anthropic:claude-sonnet-4-20250514"
        }

  ### Options

  - `:system_prompt` (optional) - Custom system prompt for CoT reasoning
  - `:model` (optional) - Model identifier, defaults to "anthropic:claude-haiku-4-5"

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"cot.query"` → `:cot_start`
  - `"reqllm.result"` → `:cot_llm_result`
  - `"reqllm.partial"` → `:cot_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with the following shape:

      %{
        status: :idle | :reasoning | :completed | :error,
        prompt: String.t() | nil,
        steps: [%{number: integer(), content: String.t()}],
        conclusion: String.t() | nil,
        raw_response: String.t() | nil,
        result: String.t() | nil,
        current_call_id: String.t() | nil,
        termination_reason: :success | :error | nil,
        config: config()
      }
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.ChainOfThought.Machine
  alias Jido.AI.Directive
  alias Jido.AI.Strategy.StateOpsHelpers
  alias ReqLLM.Context

  @type config :: %{
          system_prompt: String.t(),
          model: String.t()
        }

  @default_model "anthropic:claude-haiku-4-5"

  @start :cot_start
  @llm_result :cot_llm_result
  @llm_partial :cot_llm_partial

  @doc "Returns the action atom for starting a CoT reasoning session."
  @spec start_action() :: :cot_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :cot_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :cot_llm_partial
  def llm_partial_action, do: @llm_partial

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string()}),
      doc: "Start a new Chain-of-Thought reasoning session",
      name: "cot.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response with reasoning steps",
      name: "cot.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "cot.llm_partial"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"cot.query", {:strategy_cmd, @start}},
      {"reqllm.result", {:strategy_cmd, @llm_result}},
      {"reqllm.partial", {:strategy_cmd, @llm_partial}},
      # Usage report is emitted for observability but doesn't need processing
      {"ai.usage_report", Jido.Actions.Control.Noop}
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
      steps: state[:steps],
      steps_count: length(state[:steps] || []),
      conclusion: state[:conclusion],
      streaming_text: state[:streaming_text],
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
  defp empty_value?(_), do: false

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)
    machine = Machine.new()

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

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    case to_machine_msg(normalize_action(action), params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        env = %{
          system_prompt: config[:system_prompt]
        }

        {machine, directives} = Machine.update(machine, msg, env)

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

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{prompt: prompt}) do
    call_id = generate_call_id()
    {:start, prompt, call_id}
  end

  defp to_machine_msg(@llm_result, %{call_id: call_id, result: result}) do
    {:llm_result, call_id, result}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type}) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp lift_directives(directives, config) do
    %{model: model} = config

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        [
          Directive.ReqLLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: []
          })
        ]

      # Issue #9 fix: Handle request rejection when agent is busy
      {:request_error, call_id, reason, message} ->
        [
          Directive.EmitRequestError.new!(%{
            call_id: call_id,
            reason: reason,
            message: message
          })
        ]
    end)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    # Resolve model - can be an alias atom or a full spec string
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    # Get system prompt
    system_prompt = Keyword.get(opts, :system_prompt, Machine.default_system_prompt())

    %{
      system_prompt: system_prompt,
      model: resolved_model
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp generate_call_id, do: Machine.generate_call_id()

  @doc """
  Returns the extracted reasoning steps from the agent's current state.
  """
  @spec get_steps(Agent.t()) :: [Machine.step()]
  def get_steps(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:steps] || []
  end

  @doc """
  Returns the conclusion from the agent's current state.
  """
  @spec get_conclusion(Agent.t()) :: String.t() | nil
  def get_conclusion(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:conclusion]
  end

  @doc """
  Returns the raw LLM response from the agent's current state.
  """
  @spec get_raw_response(Agent.t()) :: String.t() | nil
  def get_raw_response(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:raw_response]
  end
end
