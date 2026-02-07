if Code.ensure_loaded?(AgentSessionManager.SessionManager) do
  defmodule Jido.AI.Directive.AgentSessionLiveTest do
    @moduledoc """
    Live tests for AgentSession directive against real CLI adapters.

    Excluded by default. Run with:

        mix test --include requires_claude_code_cli
        mix test --include requires_codex_cli
        mix test --include requires_claude_code_cli --include requires_codex_cli

    Requires the Claude Code CLI (`claude`) or Codex CLI (`codex`) to be
    installed and authenticated.
    """
    use ExUnit.Case, async: false

    alias Jido.AgentServer.DirectiveExec
    alias Jido.AI.Directive.AgentSession

    # Collect signals until we see a terminal one (completed/failed) or timeout.
    # Prints each signal type as it arrives for visibility.
    defp collect_signals(timeout) do
      deadline = System.monotonic_time(:millisecond) + timeout
      do_collect([], deadline)
    end

    defp do_collect(acc, deadline) do
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:"$gen_cast", {:signal, signal}} ->
          IO.puts("  >> #{signal.type}: #{signal_summary(signal)}")
          acc = [signal | acc]

          if signal.type in ["ai.agent_session.completed", "ai.agent_session.failed"] do
            Enum.reverse(acc)
          else
            do_collect(acc, deadline)
          end
      after
        remaining -> Enum.reverse(acc)
      end
    end

    defp signal_summary(%{type: "ai.agent_session.message"} = s) do
      content = s.data.content
      truncated = if String.length(content) > 80, do: String.slice(content, 0, 80) <> "...", else: content
      "#{if s.data.delta, do: "delta", else: "full"} | #{truncated}"
    end

    defp signal_summary(%{type: "ai.agent_session.completed"} = s) do
      inspect(s.data.output) |> String.slice(0, 100)
    end

    defp signal_summary(%{type: "ai.agent_session.failed"} = s) do
      "#{s.data.reason}: #{s.data.error_message}"
    end

    defp signal_summary(%{type: "ai.agent_session.tool_call"} = s) do
      "#{s.data.tool_name} (#{s.data.status})"
    end

    defp signal_summary(s), do: inspect(Map.delete(s.data, :metadata))

    defp build_state do
      {:ok, supervisor} = Task.Supervisor.start_link()
      %{task_supervisor: supervisor}
    end

    describe "ClaudeAdapter live" do
      @tag :requires_claude_code_cli
      test "executes a simple prompt and streams signals" do
        directive =
          AgentSession.new!(%{
            id: "live-claude-test",
            adapter: AgentSessionManager.Adapters.ClaudeAdapter,
            input: "What is 2 + 2? Reply with just the number.",
            timeout: 30_000,
            emit_events: true,
            metadata: %{test: "live_claude"}
          })

        state = build_state()
        exec_impl = DirectiveExec.impl_for!(directive)
        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        signals = collect_signals(30_000)
        signal_types = Enum.map(signals, & &1.type)

        assert not Enum.empty?(signals), "Expected at least one signal"

        assert "ai.agent_session.completed" in signal_types or
                 "ai.agent_session.failed" in signal_types

        if "ai.agent_session.completed" in signal_types do
          completed = Enum.find(signals, &(&1.type == "ai.agent_session.completed"))
          assert completed.data.output != nil
          assert is_binary(completed.data.session_id)
          assert is_binary(completed.data.run_id)
        end
      end
    end

    describe "CodexAdapter live" do
      @tag :requires_codex_cli
      test "executes a simple prompt and streams signals" do
        directive =
          AgentSession.new!(%{
            id: "live-codex-test",
            adapter: AgentSessionManager.Adapters.CodexAdapter,
            input: "What is 2 + 2? Reply with just the number.",
            timeout: 30_000,
            emit_events: true,
            session_config: %{working_directory: File.cwd!()},
            metadata: %{test: "live_codex"}
          })

        state = build_state()
        exec_impl = DirectiveExec.impl_for!(directive)
        exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

        signals = collect_signals(30_000)
        signal_types = Enum.map(signals, & &1.type)

        assert not Enum.empty?(signals), "Expected at least one signal"

        assert "ai.agent_session.completed" in signal_types or
                 "ai.agent_session.failed" in signal_types
      end
    end
  end
end
