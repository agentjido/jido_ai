defmodule Jido.AI.Strategies.ReAct do
  @moduledoc """
  Generic ReAct (Reason-Act) execution strategy for Jido agents.

  This strategy implements a multi-step reasoning loop:
  1. User query arrives -> Start LLM call with tools
  2. LLM response -> Either tool calls or final answer
  3. Tool results -> Continue with next LLM call
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
          Jido.AI.Strategies.ReAct,
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

  - `"react.user_query"` -> `:react_start`
  - `"reqllm.result"` -> `:react_llm_result`
  - `"ai.tool_result"` -> `:react_tool_result`
  - `"reqllm.partial"` -> `:react_llm_partial`

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
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.Config
  alias Jido.AI.Directive
  alias Jido.AI.ReAct.Machine
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Tools.Registry
  alias ReqLLM.Context

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer(),
          use_registry: boolean()
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
  @register_tool :react_register_tool
  @unregister_tool :react_unregister_tool

  @doc "Returns the action atom for starting a ReAct conversation."
  @spec start_action() :: :react_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :react_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for registering a tool dynamically."
  @spec register_tool_action() :: :react_register_tool
  def register_tool_action, do: @register_tool

  @doc "Returns the action atom for unregistering a tool."
  @spec unregister_tool_action() :: :react_unregister_tool
  def unregister_tool_action, do: @unregister_tool

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
    },
    @register_tool => %{
      schema: Zoi.object(%{tool_module: Zoi.atom()}),
      doc: "Register a new tool dynamically at runtime",
      name: "react.register_tool"
    },
    @unregister_tool => %{
      schema: Zoi.object(%{tool_name: Zoi.string()}),
      doc: "Unregister a tool by name",
      name: "react.unregister_tool"
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

    # Calculate duration if we have started_at
    duration_ms =
      case state[:started_at] do
        nil -> nil
        started_at -> System.monotonic_time(:millisecond) - started_at
      end

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
          streaming_thinking: state[:streaming_thinking],
          usage: state[:usage],
          duration_ms: duration_ms
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == %{} end)
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
    normalized_action = normalize_action(action)

    # Handle tool registration/unregistration separately (not machine messages)
    case normalized_action do
      @register_tool ->
        process_register_tool(agent, params)

      @unregister_tool ->
        process_unregister_tool(agent, params)

      _ ->
        case to_machine_msg(normalized_action, params) do
          msg when not is_nil(msg) ->
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
              |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

            agent = StratState.put(agent, new_state)
            {agent, lift_directives(directives, config)}

          _ ->
            :noop
        end
    end
  end

  defp process_register_tool(agent, %{tool_module: module}) when is_atom(module) do
    state = StratState.get(agent, %{})
    config = state[:config]

    # Add the tool to the config
    new_tools = [module | config[:tools]] |> Enum.uniq()
    new_actions_by_name = Map.put(config[:actions_by_name], module.name(), module)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      StateOpsHelpers.apply_to_state(state, StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools))

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_unregister_tool(agent, %{tool_name: tool_name}) when is_binary(tool_name) do
    state = StratState.get(agent, %{})
    config = state[:config]

    # Remove the tool from the config
    new_tools = Enum.reject(config[:tools], fn m -> m.name() == tool_name end)
    new_actions_by_name = Map.delete(config[:actions_by_name], tool_name)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      StateOpsHelpers.apply_to_state(state, StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools))

    agent = StratState.put(agent, new_state)
    {agent, []}
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
        case lookup_tool(tool_name, actions_by_name, config) do
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

  # Looks up a tool by name, first in actions_by_name, then optionally in Registry
  defp lookup_tool(tool_name, actions_by_name, config) do
    case Map.fetch(actions_by_name, tool_name) do
      {:ok, _module} = result ->
        result

      :error ->
        lookup_in_registry(tool_name, config)
    end
  end

  defp lookup_in_registry(tool_name, config) do
    if config[:use_registry] do
      case Registry.get(tool_name) do
        {:ok, {:action, module}} -> {:ok, module}
        {:ok, {:tool, module}} -> {:ok, module}
        _ -> :error
      end
    else
      :error
    end
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
                "Jido.AI.Strategies.ReAct requires :tools option (list of Jido.Action modules)"
      end

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    # Resolve model - can be an alias atom (:fast, :capable) or a full spec string
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    # Whether to also use Registry for tool lookup (for exec_tool fallback)
    use_registry = Keyword.get(opts, :use_registry, false)

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      system_prompt: Keyword.get(opts, :system_prompt, @default_system_prompt),
      model: resolved_model,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      use_registry: use_registry
    }
  end

  # Resolves model aliases to full specs, passes through strings unchanged
  defp resolve_model_spec(model) when is_atom(model) do
    Config.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp generate_call_id, do: Machine.generate_call_id()

  @doc """
  Returns the list of currently registered tools for the given agent.
  """
  @spec list_tools(Agent.t()) :: [module()]
  def list_tools(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    config[:tools] || []
  end
end
