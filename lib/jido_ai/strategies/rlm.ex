defmodule Jido.AI.Strategies.RLM do
  @moduledoc """
  RLM (Recursive Language Model) execution strategy for Jido agents.

  Implements iterative context exploration with sub-LLM delegation using native
  BEAM/Jido semantics. Uses the ReAct state machine internally for the
  awaiting_llm ↔ awaiting_tool cycle, adding RLM-specific tools, prompts,
  and context/workspace management.

  ## Configuration

      use Jido.Agent,
        name: "my_rlm_agent",
        strategy: {
          Jido.AI.Strategies.RLM,
          model: "anthropic:claude-sonnet-4-20250514",
          recursive_model: "anthropic:claude-haiku-4-5",
          max_iterations: 15,
          extra_tools: []
        }

  ## Workspace & Context Lifecycle

  Workspace and context can be managed independently of queries:

      # Create workspace ahead of time
      signal = Jido.Signal.new!("rlm.workspace.create", %{})
      # ... workspace_ref returned via directive

      # Load context separately
      signal = Jido.Signal.new!("rlm.context.load", %{context: large_binary})
      # ... context_ref returned via directive

      # Run query with pre-existing refs
      signal = Jido.Signal.new!("rlm.explore", %{
        query: "find the answer",
        workspace_ref: workspace_ref,
        context_ref: context_ref
      })

      # Cleanup when done (caller's responsibility for externally-created refs)
      signal = Jido.Signal.new!("rlm.workspace.delete", %{workspace_ref: workspace_ref})
      signal = Jido.Signal.new!("rlm.context.delete", %{context_ref: context_ref})
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.ReAct.Machine
  alias Jido.AI.RLM.{BudgetStore, ContextStore, PartialCollector, Reaper, WorkspaceStore, Prompts}
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.ToolAdapter
  alias ReqLLM.Context

  @rlm_tools [
    Jido.AI.Actions.RLM.Context.Stats,
    Jido.AI.Actions.RLM.Context.Chunk,
    Jido.AI.Actions.RLM.Context.ReadChunk,
    Jido.AI.Actions.RLM.Context.Search,
    Jido.AI.Actions.RLM.Workspace.Note,
    Jido.AI.Actions.RLM.Workspace.GetSummary,
    Jido.AI.Actions.RLM.LLM.SubqueryBatch
  ]

  @default_model "anthropic:claude-sonnet-4-20250514"
  @default_recursive_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 15
  @default_context_inline_threshold 2_000_000
  @default_max_concurrency 10
  @default_orchestration_mode :auto

  @start :rlm_start
  @llm_result :rlm_llm_result
  @tool_result :rlm_tool_result
  @llm_partial :rlm_llm_partial
  @workspace_create :rlm_workspace_create
  @workspace_delete :rlm_workspace_delete
  @context_load :rlm_context_load
  @context_delete :rlm_context_delete
  @usage :rlm_usage
  @fanout_complete :rlm_fanout_complete

  @spec start_action() :: :rlm_start
  def start_action, do: @start

  @spec llm_result_action() :: :rlm_llm_result
  def llm_result_action, do: @llm_result

  @spec tool_result_action() :: :rlm_tool_result
  def tool_result_action, do: @tool_result

  @spec llm_partial_action() :: :rlm_llm_partial
  def llm_partial_action, do: @llm_partial

  @spec workspace_create_action() :: :rlm_workspace_create
  def workspace_create_action, do: @workspace_create

  @spec workspace_delete_action() :: :rlm_workspace_delete
  def workspace_delete_action, do: @workspace_delete

  @spec context_load_action() :: :rlm_context_load
  def context_load_action, do: @context_load

  @spec context_delete_action() :: :rlm_context_delete
  def context_delete_action, do: @context_delete

  @spec usage_action() :: :rlm_usage
  def usage_action, do: @usage

  @spec fanout_complete_action() :: :rlm_fanout_complete
  def fanout_complete_action, do: @fanout_complete

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          query: Zoi.string(),
          context: Zoi.any() |> Zoi.optional(),
          context_ref: Zoi.map() |> Zoi.optional(),
          workspace_ref: Zoi.map() |> Zoi.optional(),
          tool_context: Zoi.map() |> Zoi.optional()
        }),
      doc: "Start RLM context exploration with a query and large context",
      name: "rlm.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "rlm.llm_result"
    },
    @tool_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Handle tool execution result",
      name: "rlm.tool_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token",
      name: "rlm.llm_partial"
    },
    @workspace_create => %{
      schema:
        Zoi.object(%{
          seed: Zoi.map() |> Zoi.optional()
        }),
      doc: "Create a workspace for exploration state",
      name: "rlm.workspace.create"
    },
    @workspace_delete => %{
      schema:
        Zoi.object(%{
          workspace_ref: Zoi.map()
        }),
      doc: "Delete a workspace and free its resources",
      name: "rlm.workspace.delete"
    },
    @context_load => %{
      schema:
        Zoi.object(%{
          context: Zoi.any(),
          workspace_ref: Zoi.map() |> Zoi.optional()
        }),
      doc: "Load context into a store and return a reference",
      name: "rlm.context.load"
    },
    @context_delete => %{
      schema:
        Zoi.object(%{
          context_ref: Zoi.map()
        }),
      doc: "Delete context and free its resources",
      name: "rlm.context.delete"
    },
    @usage => %{
      schema:
        Zoi.object(%{
          usage: Zoi.any() |> Zoi.optional(),
          total_tokens: Zoi.integer() |> Zoi.optional(),
          input_tokens: Zoi.integer() |> Zoi.optional(),
          output_tokens: Zoi.integer() |> Zoi.optional(),
          model: Zoi.string() |> Zoi.optional(),
          call_id: Zoi.string() |> Zoi.optional(),
          metadata: Zoi.any() |> Zoi.optional()
        }),
      doc: "Handle LLM usage/token tracking",
      name: "rlm.usage"
    },
    @fanout_complete => %{
      schema:
        Zoi.object(%{
          chunk_count: Zoi.integer() |> Zoi.optional(),
          completed: Zoi.integer() |> Zoi.optional(),
          errors: Zoi.integer() |> Zoi.optional(),
          skipped: Zoi.integer() |> Zoi.optional()
        }),
      doc: "Handle completion of runtime-driven parallel fan-out",
      name: "rlm.fanout_complete"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"rlm.explore", {:strategy_cmd, @start}},
      {"react.llm.response", {:strategy_cmd, @llm_result}},
      {"react.tool.result", {:strategy_cmd, @tool_result}},
      {"react.llm.delta", {:strategy_cmd, @llm_partial}},
      {"react.usage", {:strategy_cmd, @usage}},
      {"rlm.workspace.create", {:strategy_cmd, @workspace_create}},
      {"rlm.workspace.delete", {:strategy_cmd, @workspace_delete}},
      {"rlm.context.load", {:strategy_cmd, @context_load}},
      {"rlm.context.delete", {:strategy_cmd, @context_delete}},
      {"rlm.fanout_complete", {:strategy_cmd, @fanout_complete}}
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
  defp snapshot_status(:preparing), do: :running
  defp snapshot_status(:synthesizing), do: :running
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
      workspace_ref: state[:workspace_ref],
      context_ref: state[:context_ref],
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

    case normalized_action do
      @start ->
        state = StratState.get(agent, %{})
        config = state[:config]

        if state[:status] in [:preparing, :synthesizing] do
          call_id = Machine.generate_call_id()

          {agent,
           [
             {:request_error, call_id, :busy, "Agent is busy (#{state[:status]})"}
           ]}
        else
          workspace_ref =
            case Map.get(params, :workspace_ref) do
              nil ->
                request_id = Jido.Util.generate_id()
                {:ok, ref} = WorkspaceStore.init(request_id)
                ref

              existing_ref when is_map(existing_ref) ->
                existing_ref
            end

          context_ref =
            cond do
              is_binary(Map.get(params, :context)) ->
                store_context(params, config, workspace_ref)

              is_map(Map.get(params, :context_ref)) ->
                params.context_ref

              true ->
                nil
            end

          owns_workspace = is_nil(Map.get(params, :workspace_ref))
          owns_context = is_nil(Map.get(params, :context_ref))

          {budget_ref, owns_budget} =
            cond do
              not is_nil(get_in(params, [:tool_context, :budget_ref])) ->
                {get_in(params, [:tool_context, :budget_ref]), false}

              not is_nil(config[:max_children_total]) or not is_nil(config[:token_budget]) ->
                request_id = Jido.Util.generate_id()

                {:ok, ref} =
                  BudgetStore.new(request_id,
                    max_children_total: config[:max_children_total],
                    token_budget: config[:token_budget]
                  )

                {ref, true}

              true ->
                {nil, false}
            end

          reaper_alive? = Process.whereis(Jido.AI.RLM.Reaper) != nil
          resource_ttl_ms = config[:resource_ttl_ms]

          if reaper_alive? and not is_nil(resource_ttl_ms) do
            if owns_workspace, do: Reaper.track({:workspace, workspace_ref}, resource_ttl_ms)
            if owns_context and not is_nil(context_ref), do: Reaper.track({:context, context_ref}, resource_ttl_ms)
            if owns_budget and not is_nil(budget_ref), do: Reaper.track({:budget, budget_ref}, resource_ttl_ms)
          end

          run_context =
            (Map.get(params, :tool_context) || %{})
            |> Map.put(:context_ref, context_ref)
            |> Map.put(:workspace_ref, workspace_ref)
            |> Map.put(:recursive_model, config[:recursive_model])
            |> Map.put(:chunk_defaults, chunk_defaults(config))
            |> Map.put(:current_depth, get_in(params, [:tool_context, :current_depth]) || 0)
            |> Map.put(:max_depth, config[:max_depth])
            |> Map.put(:child_agent, config[:child_agent])
            |> then(fn ctx -> if budget_ref, do: Map.put(ctx, :budget_ref, budget_ref), else: ctx end)

          agent = set_run_tool_context(agent, run_context)

          agent =
            store_rlm_state(agent, %{
              query: params.query,
              context_ref: context_ref,
              workspace_ref: workspace_ref
            })

          state = StratState.get(agent, %{})

          new_state =
            state
            |> Map.put(:owns_workspace, owns_workspace)
            |> Map.put(:owns_context, owns_context)
            |> Map.put(:budget_ref, budget_ref)
            |> Map.put(:owns_budget, owns_budget)

          agent = StratState.put(agent, new_state)

          if config[:parallel_mode] == :runtime and config[:max_depth] > 0 and not is_nil(context_ref) do
            start_prepare_phase(agent, config, params, context_ref, workspace_ref, run_context)
          else
            agent = maybe_auto_spawn(agent, config, context_ref, workspace_ref, run_context, params)
            process_machine_message(agent, normalized_action, params)
          end
        end

      @fanout_complete ->
        handle_fanout_complete(agent, params)

      @workspace_create ->
        state = StratState.get(agent, %{})
        seed = Map.get(params, :seed, %{})
        request_id = Jido.Util.generate_id()
        {:ok, workspace_ref} = WorkspaceStore.init(request_id, seed)

        agent =
          store_rlm_state(agent, %{
            query: state[:query],
            context_ref: state[:context_ref],
            workspace_ref: workspace_ref
          })

        {agent, [{:workspace_created, workspace_ref}]}

      @workspace_delete ->
        state = StratState.get(agent, %{})
        workspace_ref = Map.get(params, :workspace_ref) || state[:workspace_ref]

        if workspace_ref do
          WorkspaceStore.delete(workspace_ref)

          agent =
            if state[:workspace_ref] == workspace_ref do
              store_rlm_state(agent, %{
                query: state[:query],
                context_ref: state[:context_ref],
                workspace_ref: nil
              })
            else
              agent
            end

          {agent, [{:workspace_deleted, workspace_ref}]}
        else
          {agent, []}
        end

      @context_load ->
        state = StratState.get(agent, %{})
        config = state[:config]
        context = params.context
        workspace_ref = Map.get(params, :workspace_ref) || state[:workspace_ref]

        context_ref =
          if is_binary(context) do
            store_context(%{context: context}, config, workspace_ref)
          else
            nil
          end

        agent =
          store_rlm_state(agent, %{
            query: state[:query],
            context_ref: context_ref,
            workspace_ref: state[:workspace_ref]
          })

        {agent, [{:context_loaded, context_ref}]}

      @context_delete ->
        state = StratState.get(agent, %{})
        context_ref = Map.get(params, :context_ref) || state[:context_ref]

        if context_ref do
          ContextStore.delete(context_ref)

          agent =
            if state[:context_ref] == context_ref do
              store_rlm_state(agent, %{
                query: state[:query],
                context_ref: nil,
                workspace_ref: state[:workspace_ref]
              })
            else
              agent
            end

          {agent, [{:context_deleted, context_ref}]}
        else
          {agent, []}
        end

      @usage ->
        state = StratState.get(agent, %{})
        budget_ref = state[:budget_ref]
        tokens = extract_total_tokens(params)

        agent =
          if budget_ref && tokens > 0 do
            case BudgetStore.add_tokens(budget_ref, tokens) do
              :ok ->
                agent

              {:error, :token_budget_exceeded} ->
                new_state = Map.put(state, :budget_exceeded, true)
                StratState.put(agent, new_state)
            end
          else
            agent
          end

        {agent, []}

      @tool_result ->
        state = StratState.get(agent, %{})

        if state[:status] == :preparing do
          handle_prepare_tool_result(agent, state, params)
        else
          process_machine_message(agent, normalized_action, params)
        end

      _ ->
        process_machine_message(agent, normalized_action, params)
    end
  end

  defp start_prepare_phase(agent, config, params, context_ref, workspace_ref, run_context) do
    chunk_call_id = "prepare_chunk_#{Jido.Util.generate_id()}"

    state = StratState.get(agent, %{})

    new_state =
      state
      |> Map.put(:status, :preparing)
      |> Map.put(:prepare, %{
        phase: :chunking,
        chunk_call_id: chunk_call_id,
        spawn_call_id: nil,
        query: params.query,
        run_context: run_context
      })
      |> Map.put(:started_at, System.monotonic_time(:millisecond))

    agent = StratState.put(agent, new_state)

    chunk_directive =
      Directive.ToolExec.new!(%{
        id: chunk_call_id,
        tool_name: "context_chunk",
        action_module: Jido.AI.Actions.RLM.Context.Chunk,
        arguments: %{
          "strategy" => config[:chunk_strategy] || "lines",
          "size" => config[:chunk_size] || 1000,
          "overlap" => config[:chunk_overlap] || 0,
          "max_chunks" => config[:prepare_max_chunks] || config[:max_chunks] || 500,
          "preview_bytes" => config[:chunk_preview_bytes] || 100
        },
        context: %{
          context_ref: context_ref,
          workspace_ref: workspace_ref
        }
      })

    {agent, [chunk_directive]}
  end

  defp handle_prepare_tool_result(agent, state, params) do
    prepare = state[:prepare] || %{}
    call_id = params[:call_id]

    cond do
      prepare[:phase] == :chunking and call_id == prepare[:chunk_call_id] ->
        handle_chunk_result(agent, state, prepare, params)

      prepare[:phase] == :spawning and call_id == prepare[:spawn_call_id] ->
        handle_spawn_result(agent, state, prepare, params)

      true ->
        process_machine_message(agent, @tool_result, params)
    end
  end

  defp handle_chunk_result(agent, state, prepare, params) do
    config = state[:config]
    run_context = prepare[:run_context]

    {chunk_ids, projection_id} =
      case params[:result] do
        {:ok, %{chunks: chunks} = result} -> {Enum.map(chunks, & &1.id), result[:projection_id]}
        _ -> {[], nil}
      end

    if chunk_ids == [] do
      new_state =
        state
        |> Map.put(:status, :idle)
        |> Map.delete(:prepare)

      agent = StratState.put(agent, new_state)
      process_machine_message(agent, @start, %{query: prepare[:query]})
    else
      spawn_call_id = "prepare_spawn_#{Jido.Util.generate_id()}"

      new_prepare =
        prepare
        |> Map.put(:phase, :spawning)
        |> Map.put(:spawn_call_id, spawn_call_id)
        |> Map.put(:chunk_count, length(chunk_ids))

      new_state = Map.put(state, :prepare, new_prepare)
      agent = StratState.put(agent, new_state)

      spawn_context =
        run_context
        |> Map.put(:current_depth, run_context[:max_depth] || 1)

      spawn_directive =
        Directive.ToolExec.new!(%{
          id: spawn_call_id,
          tool_name: "rlm_spawn_agent",
          action_module: Jido.AI.Actions.RLM.Agent.Spawn,
          arguments:
            %{
              "chunk_ids" => chunk_ids,
              "query" => prepare[:query],
              "max_iterations" => config[:child_max_iterations] || 8,
              "timeout" => config[:child_timeout] || 120_000,
              "max_concurrency" => config[:max_concurrency] || @default_max_concurrency,
              "max_chunk_bytes" => config[:max_chunk_bytes] || 100_000
            }
            |> then(fn args ->
              if projection_id, do: Map.put(args, "projection_id", projection_id), else: args
            end),
          context: spawn_context
        })

      {agent, [spawn_directive]}
    end
  end

  defp handle_spawn_result(agent, state, prepare, params) do
    {completed, errors, skipped} =
      case params[:result] do
        {:ok, result} ->
          {result[:completed] || 0, result[:errors] || 0, result[:skipped] || 0}

        _ ->
          {0, 1, 0}
      end

    new_state =
      state
      |> Map.put(:status, :synthesizing)
      |> Map.delete(:prepare)

    agent = StratState.put(agent, new_state)

    start_synthesis(agent, new_state, %{
      chunk_count: prepare[:chunk_count] || 0,
      completed: completed,
      errors: errors,
      skipped: skipped
    })
  end

  defp handle_fanout_complete(agent, params) do
    state = StratState.get(agent, %{})

    new_state =
      state
      |> Map.put(:status, :synthesizing)
      |> Map.delete(:prepare)

    agent = StratState.put(agent, new_state)
    start_synthesis(agent, new_state, params)
  end

  defp start_synthesis(agent, state, params) do
    config = state[:config]

    workspace_summary =
      case state[:workspace_ref] do
        nil -> ""
        ref -> WorkspaceStore.summary(ref, max_chars: 16_000)
      end

    synthesis_query =
      Prompts.synthesis_prompt(%{
        original_query: state[:query],
        workspace_summary: workspace_summary,
        chunk_count: params[:chunk_count] || 0,
        completed: params[:completed] || 0,
        errors: params[:errors] || 0
      })

    synthesis_config =
      config
      |> Map.put(:max_iterations, 1)
      |> Map.put(:reqllm_tools, [])
      |> Map.put(:actions_by_name, %{})
      |> Map.put(
        :system_prompt,
        "You are a precise synthesizer. Combine child analysis results into a single coherent answer. You have no tools available."
      )

    machine = Machine.new()

    new_state =
      state
      |> Map.merge(Machine.to_map(machine))
      |> Map.put(:config, synthesis_config)

    agent = StratState.put(agent, new_state)

    process_machine_message(agent, @start, %{query: synthesis_query.content})
  end

  defp process_machine_message(agent, action, params) do
    case to_machine_msg(action, params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        env = %{
          system_prompt: config[:system_prompt],
          max_iterations: config[:max_iterations]
        }

        {machine, directives} = Machine.update(machine, msg, env)

        machine_state = Machine.to_map(machine)

        new_state =
          machine_state
          |> Map.put(:run_tool_context, state[:run_tool_context])
          |> Map.put(:query, state[:query])
          |> Map.put(:context_ref, state[:context_ref])
          |> Map.put(:workspace_ref, state[:workspace_ref])
          |> Map.put(:owns_workspace, state[:owns_workspace])
          |> Map.put(:owns_context, state[:owns_context])
          |> Map.put(:budget_ref, state[:budget_ref])
          |> Map.put(:owns_budget, state[:owns_budget])
          |> Map.put(:budget_exceeded, state[:budget_exceeded])
          |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

        new_state = maybe_finalize(new_state, machine_state[:status])

        maybe_emit_partial(action, params, new_state)

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config, new_state)}

      _ ->
        :noop
    end
  end

  defp maybe_emit_partial(@llm_partial, %{chunk_type: :content, delta: delta}, state) do
    with sink_pid when is_pid(sink_pid) <- get_in(state, [:run_tool_context, :partial_sink_pid]),
         chunk_id when not is_nil(chunk_id) <- get_in(state, [:run_tool_context, :chunk_id]) do
      PartialCollector.emit(sink_pid, %{
        chunk_id: chunk_id,
        type: :content,
        text: delta,
        at_ms: System.monotonic_time(:millisecond)
      })
    end

    :ok
  end

  defp maybe_emit_partial(_action, _params, _state), do: :ok

  defp lift_directives(directives, config, state) do
    %{
      model: model,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      base_tool_context: base_tool_context
    } = config

    run_tool_context = Map.get(state, :run_tool_context, %{})
    effective_tool_context = Map.merge(base_tool_context || %{}, run_tool_context)

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        workspace_summary = get_workspace_summary(state)
        iteration = state[:iteration] || 1
        current_depth = get_in(state, [:run_tool_context, :current_depth]) || 0
        max_depth_val = get_in(state, [:run_tool_context, :max_depth]) || 0

        next_step =
          Prompts.next_step_prompt(%{
            query: state[:query],
            iteration: iteration,
            workspace_summary: workspace_summary,
            current_depth: current_depth,
            max_depth: max_depth_val
          })

        augmented = conversation ++ [next_step]

        effective_tools = filter_tools_for_depth(reqllm_tools, current_depth, max_depth_val)

        [
          Directive.LLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(augmented),
            tools: effective_tools
          })
        ]

      {:exec_tool, id, tool_name, arguments} ->
        case lookup_tool(tool_name, actions_by_name) do
          {:ok, action_module} ->
            arguments = maybe_apply_tool_defaults(tool_name, arguments, config)

            exec_context =
              Map.merge(effective_tool_context, %{
                call_id: id,
                iteration: state[:iteration]
              })

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
            [
              Directive.EmitToolError.new!(%{
                id: id,
                tool_name: tool_name,
                error: {:unknown_tool, "Tool '#{tool_name}' not found in registered actions"}
              })
            ]
        end

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

  defp lookup_tool(tool_name, actions_by_name) do
    Map.fetch(actions_by_name, tool_name)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    orchestration_mode =
      normalize_orchestration_mode(Keyword.get(opts, :orchestration_mode, @default_orchestration_mode))

    extra_tools =
      case Keyword.fetch(opts, :extra_tools) do
        {:ok, mods} when is_list(mods) -> mods
        _ -> []
      end

    max_depth = Keyword.get(opts, :max_depth, 0)
    spawn_tools = spawn_tools_for(max_depth, orchestration_mode)

    tools_modules = @rlm_tools ++ spawn_tools ++ extra_tools

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    raw_recursive = Keyword.get(opts, :recursive_model, @default_recursive_model)
    resolved_recursive = resolve_model_spec(raw_recursive)

    config = %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      model: resolved_model,
      recursive_model: resolved_recursive,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      context_inline_threshold: Keyword.get(opts, :context_inline_threshold, @default_context_inline_threshold),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      base_tool_context: Map.get(agent.state, :tool_context) || Keyword.get(opts, :tool_context, %{}),
      max_depth: max_depth,
      child_agent: Keyword.get(opts, :child_agent, nil),
      max_children_total: Keyword.get(opts, :max_children_total, nil),
      token_budget: Keyword.get(opts, :token_budget, nil),
      budget_ttl_ms: Keyword.get(opts, :budget_ttl_ms, nil),
      resource_ttl_ms: Keyword.get(opts, :resource_ttl_ms, nil),
      auto_spawn?: Keyword.get(opts, :auto_spawn?, false),
      auto_spawn_threshold_bytes: Keyword.get(opts, :auto_spawn_threshold_bytes, nil),
      parallel_mode: Keyword.get(opts, :parallel_mode, :llm_driven),
      orchestration_mode: orchestration_mode,
      chunk_strategy: Keyword.get(opts, :chunk_strategy, nil),
      chunk_size: Keyword.get(opts, :chunk_size, nil),
      chunk_overlap: Keyword.get(opts, :chunk_overlap, nil),
      max_chunks: Keyword.get(opts, :max_chunks, nil),
      prepare_max_chunks: Keyword.get(opts, :prepare_max_chunks, nil),
      chunk_preview_bytes: Keyword.get(opts, :chunk_preview_bytes, nil),
      enforce_chunk_defaults: Keyword.get(opts, :enforce_chunk_defaults, false),
      child_max_iterations: Keyword.get(opts, :child_max_iterations, nil),
      child_timeout: Keyword.get(opts, :child_timeout, nil),
      max_chunk_bytes: Keyword.get(opts, :max_chunk_bytes, nil)
    }

    system_prompt = Prompts.system_prompt(config)
    Map.put(config, :system_prompt, system_prompt)
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp spawn_tools_for(max_depth, _mode) when max_depth <= 0, do: []

  defp spawn_tools_for(_max_depth, :lua_only), do: [Jido.AI.Actions.RLM.Orchestrate.LuaPlan]
  defp spawn_tools_for(_max_depth, :spawn_only), do: [Jido.AI.Actions.RLM.Agent.Spawn]

  defp spawn_tools_for(_max_depth, _mode) do
    [Jido.AI.Actions.RLM.Agent.Spawn, Jido.AI.Actions.RLM.Orchestrate.LuaPlan]
  end

  defp normalize_orchestration_mode(:lua_only), do: :lua_only
  defp normalize_orchestration_mode(:spawn_only), do: :spawn_only
  defp normalize_orchestration_mode("lua_only"), do: :lua_only
  defp normalize_orchestration_mode("spawn_only"), do: :spawn_only
  defp normalize_orchestration_mode("lua"), do: :lua_only
  defp normalize_orchestration_mode("spawn"), do: :spawn_only
  defp normalize_orchestration_mode(_), do: @default_orchestration_mode

  defp maybe_apply_tool_defaults("context_chunk", arguments, config) do
    if config[:enforce_chunk_defaults] do
      arguments
      |> normalize_tool_args()
      |> maybe_put_arg("strategy", config[:chunk_strategy])
      |> maybe_put_arg("size", config[:chunk_size])
      |> maybe_put_arg("overlap", config[:chunk_overlap])
      |> maybe_put_arg("max_chunks", config[:max_chunks] || config[:prepare_max_chunks])
      |> maybe_put_arg("preview_bytes", config[:chunk_preview_bytes])
    else
      arguments
    end
  end

  defp maybe_apply_tool_defaults(_tool_name, arguments, _config), do: arguments

  defp normalize_tool_args(nil), do: %{}

  defp normalize_tool_args(arguments) when is_map(arguments) do
    Map.new(arguments, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_tool_args(_), do: %{}

  defp maybe_put_arg(arguments, _key, nil), do: arguments
  defp maybe_put_arg(arguments, key, value), do: Map.put(arguments, key, value)

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{query: query}) do
    call_id = Machine.generate_call_id()
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

  defp store_context(%{context: context}, config, workspace_ref) when is_binary(context) do
    request_id = Jido.Util.generate_id()

    {:ok, ref} =
      ContextStore.put(context, request_id,
        inline_threshold: config[:context_inline_threshold],
        workspace_ref: workspace_ref
      )

    ref
  end

  defp set_run_tool_context(agent, context) when is_map(context) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :run_tool_context, context)
    StratState.put(agent, new_state)
  end

  defp store_rlm_state(agent, %{query: query, context_ref: context_ref, workspace_ref: workspace_ref}) do
    state = StratState.get(agent, %{})

    new_state =
      state
      |> Map.put(:query, query)
      |> Map.put(:context_ref, context_ref)
      |> Map.put(:workspace_ref, workspace_ref)

    StratState.put(agent, new_state)
  end

  defp get_workspace_summary(state) do
    case state[:workspace_ref] do
      nil -> ""
      ref -> WorkspaceStore.summary(ref)
    end
  end

  defp maybe_finalize(state, status) when status in [:completed, :error] do
    final_summary =
      case state[:workspace_ref] do
        nil -> ""
        ref -> WorkspaceStore.summary(ref)
      end

    if status == :completed do
      with sink_pid when is_pid(sink_pid) <- get_in(state, [:run_tool_context, :partial_sink_pid]),
           chunk_id when not is_nil(chunk_id) <- get_in(state, [:run_tool_context, :chunk_id]) do
        PartialCollector.emit(sink_pid, %{
          chunk_id: chunk_id,
          type: :done,
          text: "",
          at_ms: System.monotonic_time(:millisecond)
        })
      end
    end

    cleanup_rlm_state(state)

    state
    |> Map.put(:final_workspace_summary, final_summary)
    |> Map.delete(:run_tool_context)
    |> Map.delete(:context_ref)
    |> Map.delete(:workspace_ref)
    |> Map.delete(:budget_ref)
    |> Map.delete(:owns_budget)
  end

  defp maybe_finalize(state, _status), do: state

  defp filter_tools_for_depth(tools, current_depth, max_depth) when current_depth >= max_depth do
    Enum.reject(tools, fn tool -> tool.name in ["rlm_spawn_agent", "rlm_lua_plan"] end)
  end

  defp filter_tools_for_depth(tools, _current_depth, _max_depth), do: tools

  defp cleanup_rlm_state(state) do
    reaper_alive? = Process.whereis(Jido.AI.RLM.Reaper) != nil

    if state[:owns_context] != false do
      if ref = state[:context_ref] do
        if reaper_alive?, do: Reaper.untrack({:context, ref})

        case ref do
          %{backend: :workspace} -> :ok
          _ -> ContextStore.delete(ref)
        end
      end
    end

    if state[:owns_workspace] != false do
      if ref = state[:workspace_ref] do
        if reaper_alive?, do: Reaper.untrack({:workspace, ref})
        WorkspaceStore.delete(ref)
      end
    end

    if state[:owns_budget] == true do
      if ref = state[:budget_ref] do
        if reaper_alive?, do: Reaper.untrack({:budget, ref})
        BudgetStore.destroy(ref)
      end
    end
  end

  defp extract_total_tokens(params) do
    cond do
      is_integer(params[:total_tokens]) ->
        params[:total_tokens]

      is_map(params[:usage]) and is_integer(params[:usage][:total_tokens]) ->
        params[:usage][:total_tokens]

      is_map(params[:usage]) and is_integer(Map.get(params[:usage], "total_tokens")) ->
        Map.get(params[:usage], "total_tokens")

      true ->
        0
    end
  end

  defp maybe_auto_spawn(agent, config, context_ref, workspace_ref, run_context, params) do
    if config[:auto_spawn?] and config[:max_depth] > 0 and not is_nil(context_ref) do
      ctx_size = ContextStore.size(context_ref)
      threshold = config[:auto_spawn_threshold_bytes]
      should_spawn = if threshold, do: ctx_size >= threshold, else: ctx_size > 0

      if should_spawn do
        case Jido.AI.Actions.RLM.Context.Chunk.run(%{}, %{
               context_ref: context_ref,
               workspace_ref: workspace_ref,
               chunk_defaults: chunk_defaults(config)
             }) do
          {:ok, %{chunks: chunks, projection_id: projection_id}} ->
            chunk_ids = Enum.map(chunks, & &1.id)

            Jido.AI.Actions.RLM.Agent.Spawn.run(
              %{chunk_ids: chunk_ids, query: params.query, projection_id: projection_id},
              run_context
            )

            agent

          {:error, _} ->
            agent
        end
      else
        agent
      end
    else
      agent
    end
  end

  defp chunk_defaults(config) do
    %{
      strategy: config[:chunk_strategy] || "lines",
      size: config[:chunk_size] || 1000,
      overlap: config[:chunk_overlap] || 0,
      max_chunks: config[:max_chunks] || config[:prepare_max_chunks] || 500,
      preview_bytes: config[:chunk_preview_bytes] || 100
    }
  end
end
