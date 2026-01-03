defmodule Jido.AI.Strategy.ReAct do
  @moduledoc """
  Generic ReAct (Reason-Act) execution strategy for Jido agents.

  This strategy implements a multi-step reasoning loop:
  1. User query arrives → Start LLM call with tools
  2. LLM response → Either tool calls or final answer
  3. Tool results → Continue with next LLM call
  4. Repeat until final answer or max iterations

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.ReAct.Machine`) for all state
  transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_react_agent",
        strategy: {
          Jido.AI.Strategy.ReAct,
          tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
          system_prompt: "You are a helpful assistant...",
          model: "anthropic:claude-haiku-4-5",
          max_iterations: 10
        }

  ### Options

  - `:tools` (required) - List of Jido.Action modules to use as tools
  - `:system_prompt` (optional) - Custom system prompt for the LLM
  - `:model` (optional) - Model identifier, defaults to agent's `:model` state or "anthropic:claude-haiku-4-5"
  - `:max_iterations` (optional) - Maximum reasoning iterations, defaults to 10

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"react.user_query"` → `:react_start`
  - `"reqllm.result"` → `:react_llm_result`
  - `"ai.tool_result"` → `:react_tool_result`
  - `"reqllm.partial"` → `:react_llm_partial`

  No custom signal handling code is needed in your agent.

  ## State

  State is stored under `agent.state.__strategy__` with the following shape:

      %{
        status: :idle | :awaiting_llm | :awaiting_tool | :completed | :error,
        iteration: non_neg_integer(),
        conversation: [ReqLLM.Message.t()],
        pending_tool_calls: [%{id: String.t(), name: String.t(), arguments: map(), result: term()}],
        final_answer: String.t() | nil,
        current_llm_call_id: String.t() | nil,
        termination_reason: :final_answer | :max_iterations | :error | nil,
        config: config()
      }
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.{Directive, ToolAdapter}
  alias Jido.AI.ReAct.Machine
  alias ReqLLM.Context

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer()
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10
  @default_system_prompt """
  You are a helpful AI assistant using the ReAct (Reason-Act) pattern.
  When you need to perform an action, use the available tools.
  When you have enough information to answer, provide your final answer directly.
  Think step by step and explain your reasoning.
  """

  @start :react_start
  @llm_result :react_llm_result
  @tool_result :react_tool_result
  @llm_partial :react_llm_partial

  @doc "Returns the action atom for starting a ReAct conversation."
  @spec start_action() :: :react_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :react_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling tool results."
  @spec tool_result_action() :: :react_tool_result
  def tool_result_action, do: @tool_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :react_llm_partial
  def llm_partial_action, do: @llm_partial

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{query: Zoi.string()}),
      doc: "Start a new ReAct conversation with a user query",
      name: "react.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response (tool calls or final answer)",
      name: "react.llm_result"
    },
    @tool_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Handle tool execution result",
      name: "react.tool_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "react.llm_partial"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"react.user_query", {:strategy_cmd, @start}},
      {"reqllm.result", {:strategy_cmd, @llm_result}},
      {"ai.tool_result", {:strategy_cmd, @tool_result}},
      {"reqllm.partial", {:strategy_cmd, @llm_partial}}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})

    status =
      case state[:status] do
        :completed -> :success
        :error -> :failure
        :idle -> :idle
        _ -> :running
      end

    done? = status in [:success, :failure]

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: done?,
      result: state[:result],
      details:
        %{
          phase: state[:status],
          iteration: state[:iteration],
          termination_reason: state[:termination_reason],
          streaming_text: state[:streaming_text],
          streaming_thinking: state[:streaming_thinking]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
        |> Map.new()
    }
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)
    machine = Machine.new()

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
            {new_agent, Enum.reverse(new_dirs) ++ acc_dirs}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    with msg when not is_nil(msg) <- to_machine_msg(normalize_action(action), params) do
      state = StratState.get(agent, %{})
      config = state[:config]
      machine = Machine.from_map(state)

      env = %{
        system_prompt: config[:system_prompt],
        max_iterations: config[:max_iterations]
      }

      {machine, directives} = Machine.update(machine, msg, env)

      new_state =
        machine
        |> Machine.to_map()
        |> Map.put(:config, config)

      agent = StratState.put(agent, new_state)
      {agent, lift_directives(directives, config)}
    else
      _ -> :noop
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{query: query}) do
    call_id = generate_call_id()
    {:start, query, call_id}
  end

  defp to_machine_msg(@llm_result, %{call_id: call_id, result: result}) do
    {:llm_result, call_id, result}
  end

  defp to_machine_msg(@tool_result, %{call_id: call_id, result: result}) do
    {:tool_result, call_id, result}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type}) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp lift_directives(directives, config) do
    %{model: model, reqllm_tools: reqllm_tools, actions_by_name: actions_by_name} = config

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        [
          Directive.ReqLLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: reqllm_tools
          })
        ]

      {:exec_tool, id, tool_name, arguments} ->
        case Map.fetch(actions_by_name, tool_name) do
          {:ok, action_module} ->
            [
              Directive.ToolExec.new!(%{
                id: id,
                tool_name: tool_name,
                action_module: action_module,
                arguments: arguments
              })
            ]

          :error ->
            []
        end
    end)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    tools_modules =
      case Keyword.fetch(opts, :tools) do
        {:ok, mods} when is_list(mods) ->
          mods

        :error ->
          raise ArgumentError,
                "Jido.AI.Strategy.ReAct requires :tools option (list of Jido.Action modules)"
      end

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      system_prompt: Keyword.get(opts, :system_prompt, @default_system_prompt),
      model: Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model)),
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations)
    }
  end

  defp generate_call_id, do: Machine.generate_call_id()
end
