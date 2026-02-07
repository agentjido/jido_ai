if Code.ensure_loaded?(AgentSessionManager.Ports.ProviderAdapter) do
  defmodule Jido.AI.Test.MockProviderAdapter do
    @moduledoc """
    Minimal mock provider adapter for integration testing of AgentSession directive.

    Supports instant and streaming execution modes with configurable failure.
    """

    @behaviour AgentSessionManager.Ports.ProviderAdapter

    use GenServer

    alias AgentSessionManager.Core.{Capability, Error}

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def set_fail_with(server, error) do
      GenServer.call(server, {:set_fail_with, error})
    end

    # ProviderAdapter callbacks

    @impl AgentSessionManager.Ports.ProviderAdapter
    def name(_adapter), do: "mock"

    @impl AgentSessionManager.Ports.ProviderAdapter
    def capabilities(_adapter) do
      {:ok, [%Capability{name: "chat", type: :tool, enabled: true}]}
    end

    @impl AgentSessionManager.Ports.ProviderAdapter
    def execute(adapter, run, session, opts \\ []) do
      timeout = Keyword.get(opts, :timeout, 60_000)
      GenServer.call(adapter, {:execute, run, session, opts}, timeout + 5_000)
    end

    @impl AgentSessionManager.Ports.ProviderAdapter
    def cancel(_adapter, run_id), do: {:ok, run_id}

    @impl AgentSessionManager.Ports.ProviderAdapter
    def validate_config(_adapter, _config), do: :ok

    # GenServer

    @impl GenServer
    def init(opts) do
      state = %{
        execution_mode: Keyword.get(opts, :execution_mode, :streaming),
        chunk_delay_ms: Keyword.get(opts, :chunk_delay_ms, 1),
        fail_with: Keyword.get(opts, :fail_with),
        model: Keyword.get(opts, :model),
        max_turns: Keyword.get(opts, :max_turns),
        notify_pid: Keyword.get(opts, :notify_pid)
      }

      if is_pid(state.notify_pid) do
        send(state.notify_pid, {:mock_adapter_init_opts, self(), opts})
      end

      {:ok, state}
    end

    @impl GenServer
    def handle_call(:name, _from, state), do: {:reply, "mock", state}

    def handle_call(:capabilities, _from, state) do
      {:reply, {:ok, [%Capability{name: "chat", type: :tool, enabled: true}]}, state}
    end

    def handle_call({:set_fail_with, error}, _from, state) do
      {:reply, :ok, %{state | fail_with: error}}
    end

    def handle_call({:execute, run, session, opts}, from, state) do
      case state.fail_with do
        nil -> do_execute(state, run, session, opts, from)
        error -> {:reply, {:error, error}, state}
      end
    end

    def handle_call({:validate_config, _config}, _from, state) do
      {:reply, :ok, state}
    end

    defp do_execute(state, run, session, opts, from) do
      case state.execution_mode do
        :instant ->
          result = build_and_emit(state, run, session, opts)
          {:reply, result, state}

        :streaming ->
          me = self()

          spawn_link(fn ->
            result = execute_streaming(state, run, session, opts)
            GenServer.reply(from, result)
            send(me, :streaming_done)
          end)

          {:noreply, state}
      end
    end

    @impl GenServer
    def handle_info(:streaming_done, state), do: {:noreply, state}

    @impl GenServer
    def terminate(_reason, state) do
      if is_pid(state.notify_pid) do
        send(state.notify_pid, {:mock_adapter_terminated, self()})
      end

      :ok
    end

    # Private

    defp build_and_emit(state, run, session, opts) do
      event_callback = Keyword.get(opts, :event_callback)
      content = "Mock response"
      model = state.model || "mock-model"

      if event_callback do
        emit(event_callback, :run_started, run, session, %{model: model})

        emit(event_callback, :message_received, run, session, %{
          content: content,
          role: "assistant"
        })

        emit(event_callback, :run_completed, run, session, %{stop_reason: "end_turn"})
      end

      {:ok, default_response(content)}
    end

    defp execute_streaming(state, run, session, opts) do
      event_callback = Keyword.get(opts, :event_callback)
      content = "Mock streaming response"
      model = state.model || "mock-model"

      if event_callback do
        emit(event_callback, :run_started, run, session, %{model: model})
        Process.sleep(state.chunk_delay_ms)

        for chunk <- chunk_string(content, 8) do
          emit(event_callback, :message_streamed, run, session, %{delta: chunk, content: chunk})
          Process.sleep(state.chunk_delay_ms)
        end

        emit(event_callback, :message_received, run, session, %{
          content: content,
          role: "assistant"
        })

        emit(event_callback, :token_usage_updated, run, session, %{
          input_tokens: 10,
          output_tokens: 20
        })

        emit(event_callback, :run_completed, run, session, %{stop_reason: "end_turn"})
      end

      {:ok, default_response(content)}
    end

    defp emit(callback, type, run, session, data) do
      callback.(%{
        type: type,
        timestamp: DateTime.utc_now(),
        session_id: session.id,
        run_id: run.id,
        data: data,
        provider: :mock
      })
    end

    defp default_response(content) do
      %{
        output: %{content: content, stop_reason: "end_turn", tool_calls: []},
        token_usage: %{input_tokens: 10, output_tokens: 20},
        events: []
      }
    end

    defp chunk_string(string, size) do
      string
      |> String.graphemes()
      |> Enum.chunk_every(size)
      |> Enum.map(&Enum.join/1)
    end
  end

  defmodule Jido.AI.Test.FailingMockProviderAdapter do
    @moduledoc """
    Mock adapter that always fails. Used to test error paths in DirectiveExec.
    """

    @behaviour AgentSessionManager.Ports.ProviderAdapter

    use GenServer

    alias AgentSessionManager.Core.{Capability, Error}

    def start_link(_opts \\ []) do
      GenServer.start_link(__MODULE__, [])
    end

    @impl AgentSessionManager.Ports.ProviderAdapter
    def name(_adapter), do: "failing_mock"

    @impl AgentSessionManager.Ports.ProviderAdapter
    def capabilities(_adapter) do
      {:ok, [%Capability{name: "chat", type: :tool, enabled: true}]}
    end

    @impl AgentSessionManager.Ports.ProviderAdapter
    def execute(adapter, run, session, opts \\ []) do
      GenServer.call(adapter, {:execute, run, session, opts})
    end

    @impl AgentSessionManager.Ports.ProviderAdapter
    def cancel(_adapter, run_id), do: {:ok, run_id}

    @impl AgentSessionManager.Ports.ProviderAdapter
    def validate_config(_adapter, _config), do: :ok

    @impl GenServer
    def init(_opts), do: {:ok, %{}}

    @impl GenServer
    def handle_call(:name, _from, state), do: {:reply, "failing_mock", state}

    def handle_call(:capabilities, _from, state) do
      {:reply, {:ok, [%Capability{name: "chat", type: :tool, enabled: true}]}, state}
    end

    def handle_call({:execute, _run, _session, _opts}, _from, state) do
      {:reply, {:error, Error.new(:provider_error, "Simulated failure")}, state}
    end

    def handle_call({:validate_config, _config}, _from, state) do
      {:reply, :ok, state}
    end
  end
end
