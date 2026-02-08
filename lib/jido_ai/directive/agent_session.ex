if Code.ensure_loaded?(AgentSessionManager.SessionManager) do
  defmodule Jido.AI.Directive.AgentSession do
    @moduledoc """
    Directive that delegates execution to an external autonomous agent.

    Unlike `Directive.LLMStream` or `Directive.LLMGenerate`, this directive does
    not manage tool calls. The external agent (Claude Code CLI, Codex CLI, or any
    `agent_session_manager` adapter) handles everything autonomously. jido_ai
    observes events as signals but does not control tool execution.

    ## Fields

    - `id` (required) - Unique directive ID for correlation
    - `adapter` (required) - `agent_session_manager` adapter module
    - `input` (required) - Prompt / task description to send to the agent
    - `session_id` (optional) - Reserved for future session resume support (currently unsupported)
    - `session_config` (optional) - Adapter-specific session configuration
    - `model` (optional) - Model identifier passed to the adapter (if supported)
    - `timeout` (optional) - Hard timeout in ms for the full delegated run (default: 300,000)
    - `max_turns` (optional) - Max-turns hint passed to adapter (if supported)
    - `emit_events` (optional) - Whether to emit intermediate events as signals (default: `true`)
    - `metadata` (optional) - Arbitrary metadata passed through to signals

    ## Relationship to Existing Directives

        Jido.AI.Directive
        ├── LLMStream        (Mode 1: streaming completion via req_llm)
        ├── LLMGenerate      (Mode 1: blocking completion via req_llm)
        ├── ToolExec         (Mode 1: execute a tool locally)
        └── AgentSession     (Mode 2: delegate to autonomous agent) ← this

    ## Usage

        directive = Jido.AI.Directive.AgentSession.new!(%{
          id: Jido.Util.generate_id(),
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Refactor the authentication module to use JWT tokens",
          model: "claude-sonnet-4-5-20250929",
          timeout: 600_000,
          session_config: %{
            allowed_tools: ["read", "write", "bash"],
            working_directory: "/path/to/project"
          }
        })
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique directive ID for correlation"),
                adapter:
                  Zoi.atom(description: "agent_session_manager adapter module (e.g. ClaudeAdapter, CodexAdapter)"),
                input: Zoi.string(description: "Prompt / task description to send to the agent"),
                session_id:
                  Zoi.string(description: "Session ID to resume; nil for new session")
                  |> Zoi.optional(),
                session_config:
                  Zoi.map(description: "Adapter-specific session configuration")
                  |> Zoi.default(%{}),
                model:
                  Zoi.string(description: "Model identifier (e.g. 'claude-sonnet-4-5-20250929')")
                  |> Zoi.optional(),
                timeout:
                  Zoi.integer(description: "Timeout in ms for the entire agent run")
                  |> Zoi.default(300_000),
                max_turns:
                  Zoi.integer(description: "Max tool-use turns the agent can take")
                  |> Zoi.optional(),
                emit_events:
                  Zoi.boolean(description: "Whether to emit intermediate events as signals")
                  |> Zoi.default(true),
                metadata:
                  Zoi.map(description: "Arbitrary metadata passed through to signals")
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new AgentSession directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid AgentSession: #{inspect(errors)}"
      end
    end
  end

  defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.AgentSession do
    @moduledoc """
    Spawns an async task to execute an autonomous agent session via
    `agent_session_manager` and sends results back to the agent as
    `ai.agent_session.*` signals.

    This implementation is fully asynchronous — it starts a task that may run
    for minutes (the agent's tool loop) and returns `{:async, ref, state}`
    immediately. Events stream back as signals via `Jido.AgentServer.cast/2`.

    Uses `SessionManager.run_once/4` for lifecycle orchestration and wraps it in a
    directive-level timeout so this directive's timeout contract is always enforced.

    ## Task Supervisor

    Uses the agent's per-instance task supervisor from `state[:task_supervisor]`,
    started automatically by Jido.AI when an agent is created.
    """

    @compile {:no_warn_undefined, AgentSessionManager.SessionManager}
    @compile {:no_warn_undefined, AgentSessionManager.Adapters.InMemorySessionStore}

    alias AgentSessionManager.SessionManager
    alias Jido.AI.Signal.AgentSession, as: Signals

    def exec(directive, _input_signal, state) do
      agent_pid = self()
      task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

      # Build execution context for signal correlation
      context = %{
        directive_id: directive.id,
        metadata: directive.metadata
      }

      Task.Supervisor.start_child(task_supervisor, fn ->
        result =
          try do
            execute_session(directive, context, agent_pid, task_supervisor)
          rescue
            e ->
              {:error, %{exception: Exception.message(e), type: e.__struct__}}
          catch
            kind, reason ->
              {:error, %{caught: kind, reason: inspect(reason)}}
          end

        # If execute_session didn't send a completion signal (i.e. it raised),
        # send a failure signal now
        case result do
          {:error, error} ->
            signal =
              Signals.failed(error, %{
                session_id: "unknown",
                run_id: "unknown",
                directive_id: directive.id,
                metadata: directive.metadata
              })

            Jido.AgentServer.cast(agent_pid, signal)

          _ ->
            :ok
        end
      end)

      {:async, nil, state}
    end

    defp execute_session(directive, context, agent_pid, task_supervisor) do
      with :ok <- validate_runtime_support(directive),
           {:ok, store, adapter} <- start_session_components(directive) do
        try do
          # Build event callback that converts events to signals.
          # Skip terminal events in the callback — run_once's return value
          # handles completed/failed with the full result.
          terminal_events = [:run_completed, :run_failed, :run_cancelled]

          callback =
            if directive.emit_events do
              fn event ->
                maybe_emit_event_signal(event, terminal_events, context, agent_pid)
              end
            else
              fn _event -> :ok end
            end

          opts = [
            context: directive.session_config,
            event_callback: callback
          ]

          input = %{messages: [%{role: "user", content: directive.input}]}

          case run_once_with_timeout(task_supervisor, store, adapter, input, directive.timeout, opts) do
            {:ok, result} ->
              signal_context =
                Map.merge(context, %{
                  session_id: result.session_id,
                  run_id: result.run_id
                })

              signal = Signals.completed(result, signal_context)
              Jido.AgentServer.cast(agent_pid, signal)
              :ok

            {:error, error} ->
              signal_context =
                Map.merge(context, %{
                  session_id: "unknown",
                  run_id: "unknown"
                })

              signal = Signals.failed(error, signal_context)
              Jido.AgentServer.cast(agent_pid, signal)
              :ok
          end
        after
          stop_process(adapter)
          stop_process(store)
        end
      else
        {:error, reason} ->
          {:error, reason}
      end
    end

    defp validate_runtime_support(%{session_id: session_id})
         when is_binary(session_id) and session_id != "" do
      {:error,
       %{
         reason: :unsupported_feature,
         message: "AgentSession session_id resume is not supported yet"
       }}
    end

    defp validate_runtime_support(_directive), do: :ok

    defp start_session_components(directive) do
      case AgentSessionManager.Adapters.InMemorySessionStore.start_link([]) do
        {:ok, store} ->
          Process.unlink(store)

          case start_adapter(directive) do
            {:ok, adapter} ->
              Process.unlink(adapter)
              {:ok, store, adapter}

            {:error, reason} ->
              stop_process(store)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp run_once_with_timeout(_task_supervisor, store, adapter, input, timeout_ms, opts) do
      run_ref = make_ref()
      caller = self()

      {pid, mon_ref} =
        spawn_monitor(fn ->
          result = SessionManager.run_once(store, adapter, input, opts)
          send(caller, {run_ref, result})
        end)

      receive do
        {^run_ref, result} ->
          Process.demonitor(mon_ref, [:flush])
          result

        {:DOWN, ^mon_ref, :process, _pid, reason} ->
          {:error, %{reason: :execution_crash, message: "AgentSession execution crashed: #{inspect(reason)}"}}
      after
        timeout_ms ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^mon_ref, :process, _pid, _reason} -> :ok
          after
            100 -> :ok
          end

          {:error, %{reason: :timeout, message: "AgentSession timed out after #{timeout_ms}ms"}}
      end
    end

    defp start_adapter(%{adapter: adapter_module} = directive) do
      adapter_opts = build_adapter_opts(adapter_module, directive)
      adapter_module.start_link(adapter_opts)
    end

    defp build_adapter_opts(AgentSessionManager.Adapters.CodexAdapter, directive) do
      common_opts = build_common_adapter_opts(directive)

      working_dir =
        get_in(directive.session_config, [:working_directory]) ||
          get_in(directive.session_config, ["working_directory"]) ||
          File.cwd!()

      Keyword.put_new(common_opts, :working_directory, working_dir)
    end

    defp build_adapter_opts(_adapter_module, directive), do: build_common_adapter_opts(directive)

    defp build_common_adapter_opts(directive) do
      directive
      |> extract_adapter_opts()
      |> maybe_put_kw(:model, directive.model)
      |> maybe_put_kw(:max_turns, directive.max_turns)
    end

    defp extract_adapter_opts(%{session_config: session_config}) when is_map(session_config) do
      case get_in(session_config, [:adapter_opts]) || get_in(session_config, ["adapter_opts"]) do
        opts when is_list(opts) ->
          opts

        opts when is_map(opts) ->
          opts
          |> Enum.reduce([], fn
            {key, value}, acc when is_atom(key) -> [{key, value} | acc]
            {_key, _value}, acc -> acc
          end)
          |> Enum.reverse()

        _ ->
          []
      end
    end

    defp extract_adapter_opts(_directive), do: []

    defp maybe_emit_event_signal(event, terminal_events, context, agent_pid) do
      if event.type not in terminal_events do
        signal_context =
          Map.merge(context, %{
            session_id: Map.get(event, :session_id) || "unknown",
            run_id: Map.get(event, :run_id) || "unknown"
          })

        signal = Signals.from_event(event, signal_context)
        Jido.AgentServer.cast(agent_pid, signal)
      end
    end

    defp stop_process(pid) when is_pid(pid) do
      GenServer.stop(pid, :normal, 500)
      :ok
    catch
      :exit, _ -> :ok
    end

    defp stop_process(_pid), do: :ok

    defp maybe_put_kw(opts, _key, nil), do: opts
    defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)
  end
end
