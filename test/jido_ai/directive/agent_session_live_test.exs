if Code.ensure_loaded?(AgentSessionManager.SessionManager) do
  defmodule Jido.AI.Directive.AgentSessionLiveTest do
    @moduledoc """
    Live tests for AgentSession directive against real CLI adapters.

    Excluded by default. Run with:

        mix test --include requires_live_agent_cli

    The test attempts all three providers (Claude, Codex, Amp). If a provider
    is unavailable (CLI missing, not authenticated, adapter init error), it is
    skipped with a clear message and the remaining providers still run.
    """
    use ExUnit.Case, async: false

    @moduletag timeout: 240_000

    alias Jido.AgentServer.DirectiveExec
    alias Jido.AI.Directive.AgentSession

    @tag :requires_live_agent_cli
    test "runs provider matrix with meaningful AgentSession interactions" do
      providers = providers()

      results =
        Enum.map(providers, fn provider ->
          case provider_available?(provider) do
            :ok ->
              run_provider_scenarios(provider)

            {:skip, reason} ->
              IO.puts("SKIP #{provider.name}: #{reason}")
              {:skipped, provider.name, reason}
          end
        end)

      ran_count = Enum.count(results, fn {status, _, _} -> status == :ok end)
      skipped_count = Enum.count(results, fn {status, _, _} -> status == :skipped end)

      IO.puts("Live provider matrix summary: ran=#{ran_count}, skipped=#{skipped_count}, total=#{length(results)}")

      assert ran_count + skipped_count == length(providers)
    end

    defp run_provider_scenarios(provider) do
      IO.puts("RUN #{provider.name}: starting live scenarios")

      streaming_signals =
        execute_interaction(provider,
          scenario: "streaming-events",
          emit_events: true,
          input: """
          You are assisting Jido AI directive integration tests.
          Summarize in 3 concise bullet points:
          1) directive pattern
          2) signal routing
          3) async task supervision
          """,
          timeout: 60_000
        )

      assert_terminal_and_core_fields!(streaming_signals, provider.name)
      assert_started_signal_present!(streaming_signals, provider.name)

      quiet_signals =
        execute_interaction(provider,
          scenario: "final-only",
          emit_events: false,
          input: "Reply exactly: ACK",
          timeout: 30_000
        )

      assert_terminal_only_when_emit_events_disabled!(quiet_signals, provider.name)

      {:ok, provider.name,
       %{streaming_signal_count: length(streaming_signals), quiet_signal_count: length(quiet_signals)}}
    end

    # Collect signals until we see a terminal one (completed/failed) or timeout.
    defp collect_signals_until_terminal(timeout) do
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

    defp execute_interaction(provider, opts) do
      flush_signal_mailbox()

      scenario = Keyword.fetch!(opts, :scenario)
      emit_events = Keyword.fetch!(opts, :emit_events)
      input = Keyword.fetch!(opts, :input)
      timeout = Keyword.fetch!(opts, :timeout)

      directive =
        AgentSession.new!(%{
          id: "live-#{provider.key}-#{scenario}",
          adapter: provider.adapter,
          input: input,
          timeout: timeout,
          emit_events: emit_events,
          session_config: provider.session_config,
          metadata: %{
            provider: provider.key,
            scenario: scenario,
            project: "jido_ai"
          }
        })

      state = build_state()
      exec_impl = DirectiveExec.impl_for!(directive)
      exec_impl.exec(directive, %Jido.Signal{type: "test", source: "/test", id: "test-input"}, state)

      collect_signals_until_terminal(timeout)
    end

    defp assert_terminal_and_core_fields!(signals, provider_name) do
      assert signals != [], "Expected at least one signal for #{provider_name}"

      terminal =
        Enum.find(signals, fn signal ->
          signal.type in ["ai.agent_session.completed", "ai.agent_session.failed"]
        end)

      assert terminal != nil, "Expected a terminal signal for #{provider_name}"
      assert is_binary(terminal.data.session_id)
      assert is_binary(terminal.data.run_id)
      assert terminal.data.metadata[:project] == "jido_ai"
      assert terminal.data.metadata[:scenario] in ["streaming-events", "final-only"]
    end

    defp assert_started_signal_present!(signals, provider_name) do
      started_signals = Enum.filter(signals, &(&1.type == "ai.agent_session.started"))

      terminal =
        Enum.find(signals, fn signal ->
          signal.type in ["ai.agent_session.completed", "ai.agent_session.failed"]
        end)

      if terminal.type == "ai.agent_session.completed" do
        assert started_signals != [],
               "Expected ai.agent_session.started when completed for #{provider_name}"
      end
    end

    defp assert_terminal_only_when_emit_events_disabled!(signals, provider_name) do
      assert length(signals) == 1,
             "Expected exactly one terminal signal when emit_events=false for #{provider_name}"

      [signal] = signals
      assert signal.type in ["ai.agent_session.completed", "ai.agent_session.failed"]
    end

    defp provider_available?(provider) do
      case provider.adapter.start_link(provider.adapter_probe_opts) do
        {:ok, adapter} ->
          safe_stop(adapter)
          :ok

        {:error, reason} ->
          {:skip, inspect(reason)}
      end
    rescue
      exception ->
        {:skip, Exception.message(exception)}
    end

    defp safe_stop(pid) when is_pid(pid) do
      GenServer.stop(pid, :normal, 500)
      :ok
    catch
      :exit, _ -> :ok
    end

    defp flush_signal_mailbox do
      receive do
        {:"$gen_cast", {:signal, _signal}} ->
          flush_signal_mailbox()
      after
        0 -> :ok
      end
    end

    defp providers do
      [
        %{
          key: :claude,
          name: "Claude",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          adapter_probe_opts: [model: "claude-haiku-4-5-20251001", tools: []],
          session_config: %{
            adapter_opts: [model: "claude-haiku-4-5-20251001", tools: []]
          }
        },
        %{
          key: :codex,
          name: "Codex",
          adapter: AgentSessionManager.Adapters.CodexAdapter,
          adapter_probe_opts: [working_directory: File.cwd!()],
          session_config: %{
            working_directory: File.cwd!(),
            adapter_opts: [working_directory: File.cwd!()]
          }
        },
        %{
          key: :amp,
          name: "Amp",
          adapter: AgentSessionManager.Adapters.AmpAdapter,
          adapter_probe_opts: [cwd: File.cwd!()],
          session_config: %{
            adapter_opts: [cwd: File.cwd!()]
          }
        }
      ]
    end
  end
end
