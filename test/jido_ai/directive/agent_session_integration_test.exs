if Code.ensure_loaded?(AgentSessionManager.SessionManager) do
  defmodule Jido.AI.Directive.AgentSessionIntegrationTest do
    @moduledoc """
    Integration tests for the AgentSession DirectiveExec implementation.

    Tests the full flow: directive → Task.Supervisor → SessionManager.run_once/4
    → events → signals → cast back to calling process.

    Uses agent_session_manager's MockProviderAdapter with :streaming mode to
    simulate realistic event delivery.
    """
    use ExUnit.Case, async: false

    alias Jido.AI.Directive.AgentSession
    alias Jido.AI.Test.MockProviderAdapter

    # Collect all signals cast to this process via GenServer.cast
    defp receive_all_signals(timeout) do
      do_receive_all_signals([], timeout)
    end

    defp do_receive_all_signals(acc, timeout) do
      receive do
        {:"$gen_cast", {:signal, signal}} ->
          do_receive_all_signals([signal | acc], timeout)
      after
        timeout -> Enum.reverse(acc)
      end
    end

    defp build_state do
      {:ok, supervisor} = Task.Supervisor.start_link()
      %{task_supervisor: supervisor}
    end

    describe "exec/3 with MockProviderAdapter (streaming)" do
      setup do
        {:ok, adapter} =
          MockProviderAdapter.start_link(
            execution_mode: :streaming,
            chunk_delay_ms: 1
          )

        directive =
          AgentSession.new!(%{
            id: "test-directive-1",
            adapter: Jido.AI.Test.MockProviderAdapter,
            input: "Hello, test agent",
            timeout: 10_000,
            metadata: %{test: true}
          })

        %{adapter: adapter, directive: directive}
      end

      test "returns {:async, nil, state}", %{directive: directive} do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        result = exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        assert {:async, nil, ^state} = result
      end

      test "delivers intermediate signals when emit_events is true", %{directive: directive} do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        # Collect all signals (give enough time for the async task)
        Process.sleep(500)
        signals = receive_all_signals(200)

        # Should have intermediate events + final Completed
        signal_types = Enum.map(signals, & &1.type)

        assert "ai.agent_session.completed" in signal_types

        # Streaming mode emits: run_started, message_streamed chunks,
        # message_received, token_usage_updated, run_completed
        # These map to Started, Message (delta), Message, Progress, Completed signals
        # Plus the final Completed from run_once success
        assert length(signals) > 1
      end

      test "final signal is Completed with session_id and run_id", %{directive: directive} do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        completed =
          Enum.find(signals, fn s ->
            s.type == "ai.agent_session.completed" and s.data.directive_id == "test-directive-1"
          end)

        assert completed != nil
        assert is_binary(completed.data.session_id)
        assert is_binary(completed.data.run_id)
        assert completed.data.output != nil
      end

      test "delivers Message signals with delta: true for streamed chunks", %{
        directive: directive
      } do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        delta_messages =
          Enum.filter(signals, fn s ->
            s.type == "ai.agent_session.message" and s.data.delta == true
          end)

        refute Enum.empty?(delta_messages)

        for msg <- delta_messages do
          assert is_binary(msg.data.content)
          assert msg.data.session_id != nil
          assert msg.data.run_id != nil
        end
      end

      test "delivers Started signal as first intermediate event", %{directive: directive} do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        started_signals =
          Enum.filter(signals, fn s -> s.type == "ai.agent_session.started" end)

        assert length(started_signals) == 1
        started = hd(started_signals)
        assert is_binary(started.data.session_id)
        assert is_binary(started.data.run_id)
      end

      test "propagates directive metadata into signals", %{directive: directive} do
        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        completed =
          Enum.find(signals, fn s ->
            s.type == "ai.agent_session.completed"
          end)

        assert completed.data.metadata == %{test: true}
        assert completed.data.directive_id == "test-directive-1"
      end
    end

    describe "exec/3 with emit_events: false" do
      test "only delivers final Completed signal" do
        {:ok, _adapter} =
          MockProviderAdapter.start_link(
            execution_mode: :instant,
            chunk_delay_ms: 0
          )

        directive =
          AgentSession.new!(%{
            id: "test-no-events",
            adapter: Jido.AI.Test.MockProviderAdapter,
            input: "Silent run",
            emit_events: false,
            timeout: 10_000
          })

        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        # Should only get the final Completed signal from the run_once success path,
        # no intermediate event signals
        signal_types = Enum.map(signals, & &1.type)

        assert "ai.agent_session.completed" in signal_types

        # No started/message/tool_call/progress signals from intermediate events
        refute "ai.agent_session.started" in signal_types
        refute "ai.agent_session.message" in signal_types
      end
    end

    describe "exec/3 with adapter failure" do
      test "delivers Failed signal when adapter returns error" do
        directive =
          AgentSession.new!(%{
            id: "test-failure",
            adapter: Jido.AI.Test.FailingMockProviderAdapter,
            input: "This will fail",
            timeout: 10_000,
            metadata: %{expect: :failure}
          })

        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        failed =
          Enum.find(signals, fn s -> s.type == "ai.agent_session.failed" end)

        assert failed != nil
        assert failed.data.reason == :error
        assert failed.data.directive_id == "test-failure"
        assert failed.data.metadata == %{expect: :failure}
      end
    end

    describe "exec/3 with instant mode" do
      test "completes successfully with instant adapter" do
        {:ok, _adapter} =
          MockProviderAdapter.start_link(execution_mode: :instant)

        directive =
          AgentSession.new!(%{
            id: "test-instant",
            adapter: Jido.AI.Test.MockProviderAdapter,
            input: "Quick task",
            timeout: 10_000
          })

        state = build_state()
        exec_impl = Jido.AgentServer.DirectiveExec.impl_for!(directive)

        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        Process.sleep(500)
        signals = receive_all_signals(200)

        signal_types = Enum.map(signals, & &1.type)
        assert "ai.agent_session.completed" in signal_types
      end
    end
  end
end
