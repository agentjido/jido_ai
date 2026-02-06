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
    - `session_id` (optional) - Session ID to resume; `nil` for new session
    - `session_config` (optional) - Adapter-specific session configuration
    - `model` (optional) - Model identifier (e.g. `"claude-sonnet-4-5-20250929"`)
    - `timeout` (optional) - Timeout in ms for the entire agent run (default: 300,000)
    - `max_turns` (optional) - Max tool-use turns the agent can take
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

    Uses `SessionManager.run_once/4` which handles the complete session lifecycle
    (create, activate, run, execute, complete/fail) in a single call.

    ## Task Supervisor

    Uses the agent's per-instance task supervisor from `state[:task_supervisor]`,
    started automatically by Jido.AI when an agent is created.
    """

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
            execute_session(directive, context, agent_pid)
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

    defp execute_session(directive, context, agent_pid) do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])
      {:ok, adapter} = start_adapter(directive)

      # Build event callback that converts events to signals
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

      # Build run_once options
      opts =
        [
          context: directive.session_config,
          event_callback: callback
        ]
        |> maybe_put(:timeout, directive.timeout)

      # Execute the full session lifecycle in one call
      case SessionManager.run_once(
             store,
             adapter,
             %{
               messages: [%{role: "user", content: directive.input}]
             },
             opts
           ) do
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
    end

    defp start_adapter(%{adapter: adapter_module} = directive) do
      adapter_opts = build_adapter_opts(adapter_module, directive)
      adapter_module.start_link(adapter_opts)
    end

    defp build_adapter_opts(AgentSessionManager.Adapters.CodexAdapter, directive) do
      working_dir =
        get_in(directive.session_config, [:working_directory]) ||
          get_in(directive.session_config, ["working_directory"]) ||
          File.cwd!()

      [working_directory: working_dir]
    end

    defp build_adapter_opts(_adapter_module, _directive), do: []

    defp maybe_emit_event_signal(event, terminal_events, context, agent_pid) do
      if event.type not in terminal_events do
        signal_context =
          Map.merge(context, %{
            session_id: event.session_id || "unknown",
            run_id: event.run_id || "unknown"
          })

        signal = Signals.from_event(event, signal_context)
        Jido.AgentServer.cast(agent_pid, signal)
      end
    end

    defp maybe_put(opts, _key, nil), do: opts
    defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  end
end
