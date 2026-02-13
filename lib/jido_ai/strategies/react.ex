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

      use Jido.AI.Agent,
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

  - `"react.input"` -> `:react_start`
  - `"react.llm.response"` -> `:react_llm_result`
  - `"react.tool.result"` -> `:react_tool_result`
  - `"react.llm.delta"` -> `:react_llm_partial`

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
        config: config(),
        run_tool_context: map() | nil  # Ephemeral per-request context
      }

  ## Tool Context

  Tool context is separated into two scopes to prevent cross-request data leakage:

  - **`base_tool_context`** (persistent, in `config`) - Set at agent definition time via
    `:tool_context` option. Represents stable context like domain modules. Updated only
    via explicit `react.set_tool_context` action (replaces, not merges).

  - **`run_tool_context`** (ephemeral, in state) - Set per-request via `tool_context:`
    option in `react.start`. Automatically cleared when the machine reaches `:completed`
    or `:error` status. Never persists across requests.

  At tool execution time, both contexts are merged (run overrides base) to produce the
  effective context passed to actions. This ensures multi-tenant isolation - a tenant's
  request context cannot leak to subsequent requests.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.ReAct.Machine
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.ToolAdapter
  alias ReqLLM.Context

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer(),
          base_tool_context: map()
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
  @set_tool_context :react_set_tool_context

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

  @doc "Returns the action atom for updating tool context."
  @spec set_tool_context_action() :: :react_set_tool_context
  def set_tool_context_action, do: @set_tool_context

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          query: Zoi.string(),
          tool_context: Zoi.map() |> Zoi.optional()
        }),
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
    },
    @set_tool_context => %{
      schema: Zoi.object(%{tool_context: Zoi.map()}),
      doc: "Update the tool context for subsequent tool executions",
      name: "react.set_tool_context"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"react.input", {:strategy_cmd, @start}},
      {"react.llm.response", {:strategy_cmd, @llm_result}},
      {"react.tool.result", {:strategy_cmd, @tool_result}},
      {"react.llm.delta", {:strategy_cmd, @llm_partial}},
      {"react.register_tool", {:strategy_cmd, @register_tool}},
      {"react.unregister_tool", {:strategy_cmd, @unregister_tool}},
      {"react.set_tool_context", {:strategy_cmd, @set_tool_context}},
      # Usage report is emitted for observability but doesn't need processing
      {"react.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})
    status = snapshot_status(state[:status])
    config = state[:config] || %{}

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: state[:result],
      details: build_snapshot_details(state, config)
    }
  end

  defp snapshot_status(:completed), do: :success
  defp snapshot_status(:error), do: :failure
  defp snapshot_status(:idle), do: :idle
  defp snapshot_status(_), do: :running

  defp build_snapshot_details(state, config) do
    %{
      phase: state[:status],
      iteration: state[:iteration],
      termination_reason: state[:termination_reason],
      streaming_text: state[:streaming_text],
      streaming_thinking: state[:streaming_thinking],
      thinking_trace: state[:thinking_trace],
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at]),
      tool_calls: format_tool_calls(state[:pending_tool_calls] || []),
      conversation: Map.get(state, :conversation, []),
      current_llm_call_id: state[:current_llm_call_id],
      model: config[:model],
      max_iterations: config[:max_iterations],
      available_tools: Enum.map(Map.get(config, :tools, []), & &1.name())
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == %{} or v == [] end)
    |> Map.new()
  end

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  defp format_tool_calls([]), do: []

  defp format_tool_calls(pending_tool_calls) do
    Enum.map(pending_tool_calls, fn tc ->
      %{
        id: tc.id,
        name: tc.name,
        arguments: tc.arguments,
        status: if(tc.result == nil, do: :running, else: :completed),
        result: tc.result
      }
    end)
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)
    machine = Machine.new()

    state =
      machine
      |> Machine.to_map()
      |> Map.put(:agent_id, Map.get(agent, :id))
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

    # Handle tool registration/unregistration/context separately (not machine messages)
    case normalized_action do
      @register_tool ->
        process_register_tool(agent, params)

      @unregister_tool ->
        process_unregister_tool(agent, params)

      @set_tool_context ->
        process_set_tool_context(agent, params)

      @start ->
        # Store per-request tool_context in run_tool_context (ephemeral, cleared on completion)
        # This does NOT mutate base_tool_context - prevents cross-request leakage
        run_context = Map.get(params, :tool_context) || %{}
        agent = set_run_tool_context(agent, run_context)

        process_machine_message(agent, normalized_action, params)

      _ ->
        process_machine_message(agent, normalized_action, params)
    end
  end

  defp process_machine_message(agent, action, params) do
    case to_machine_msg(action, params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        env = %{
          system_prompt: config[:system_prompt],
          max_iterations: config[:max_iterations],
          telemetry_metadata: %{
            agent_id: state[:agent_id] || Map.get(agent, :id),
            thread_id: thread_id_from_state(state)
          }
        }

        {machine, directives} = Machine.update(machine, msg, env)

        machine_state = Machine.to_map(machine)

        # Preserve run_tool_context through the state update
        new_state =
          machine_state
          |> Map.put(:run_tool_context, state[:run_tool_context])
          |> Map.put(:agent_id, state[:agent_id] || Map.get(agent, :id))
          |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

        # Clear run_tool_context on terminal states to prevent cross-request leakage
        new_state =
          if machine_state[:status] in [:completed, :error] do
            Map.delete(new_state, :run_tool_context)
          else
            new_state
          end

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config, state)}

      _ ->
        :noop
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
      StateOpsHelpers.apply_to_state(
        state,
        StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

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
      StateOpsHelpers.apply_to_state(
        state,
        StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_set_tool_context(agent, %{tool_context: new_context}) when is_map(new_context) do
    state = StratState.get(agent, %{})

    # REPLACE base_tool_context (not merge) to avoid indefinite key accumulation
    # Use set_config_field to replace just this field without deep merging
    new_state =
      StateOpsHelpers.apply_to_state(state, [
        StateOpsHelpers.set_config_field(:base_tool_context, new_context)
      ])

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  # Sets ephemeral per-request tool context (cleared on completion)
  defp set_run_tool_context(agent, context) when is_map(context) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :run_tool_context, context)
    StratState.put(agent, new_state)
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

  defp lift_directives(directives, config, state) do
    %{
      model: model,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      base_tool_context: base_tool_context
    } = config

    # Merge base (persistent) + run (ephemeral) context at directive emission time
    # Run context overrides base context; neither is mutated
    run_tool_context = Map.get(state, :run_tool_context, %{})
    effective_tool_context = Map.merge(base_tool_context || %{}, run_tool_context)
    agent_id = Map.get(state, :agent_id)
    thread_id = thread_id_from_state(state)

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        [
          Directive.LLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: reqllm_tools
          })
        ]

      {:exec_tool, id, tool_name, arguments} ->
        case lookup_tool(tool_name, actions_by_name, config) do
          {:ok, action_module} ->
            # Include call_id and iteration for telemetry correlation
            exec_context =
              effective_tool_context
              |> Map.merge(%{
                call_id: id,
                iteration: state[:iteration],
                agent_id: agent_id,
                thread_id: thread_id
              })
              |> Enum.reject(fn {_key, value} -> is_nil(value) end)
              |> Map.new()

            [
              Directive.ToolExec.new!(%{
                id: id,
                tool_name: tool_name,
                action_module: action_module,
                arguments: arguments,
                context: exec_context
              })
            ]

          :error ->
            # Issue #1 fix: Never silently drop - emit error result for unknown tools
            # This ensures the Machine receives a tool_result and doesn't deadlock
            [
              Directive.EmitToolError.new!(%{
                id: id,
                tool_name: tool_name,
                error: {:unknown_tool, "Tool '#{tool_name}' not found in registered actions"}
              })
            ]
        end

      # Issue #3 fix: Handle request rejection when agent is busy
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

  # Looks up a tool by name in actions_by_name
  defp lookup_tool(tool_name, actions_by_name, _config) do
    Map.fetch(actions_by_name, tool_name)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp thread_id_from_state(state) when is_map(state) do
    case Map.get(state, :thread) do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp thread_id_from_state(_), do: nil

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

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      system_prompt: Keyword.get(opts, :system_prompt, @default_system_prompt),
      model: resolved_model,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      # base_tool_context is the persistent context from agent definition
      # per-request context is stored separately in state[:run_tool_context]
      base_tool_context: Map.get(agent.state, :tool_context) || Keyword.get(opts, :tool_context, %{})
    }
  end

  # Resolves model aliases to full specs, passes through strings unchanged
  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
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
