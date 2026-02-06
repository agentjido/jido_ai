defmodule Jido.AI.Directive.AgentSessionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive.AgentSession

  describe "AgentSession" do
    test "creates directive with required fields" do
      directive =
        AgentSession.new!(%{
          id: "dir_123",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Refactor the authentication module"
        })

      assert directive.id == "dir_123"
      assert directive.adapter == AgentSessionManager.Adapters.ClaudeAdapter
      assert directive.input == "Refactor the authentication module"
      assert directive.timeout == 300_000
      assert directive.emit_events == true
      assert directive.session_config == %{}
      assert directive.metadata == %{}
    end

    test "creates directive with session_id for resume" do
      directive =
        AgentSession.new!(%{
          id: "dir_456",
          adapter: AgentSessionManager.Adapters.CodexAdapter,
          input: "Continue the refactoring",
          session_id: "sess_abc123"
        })

      assert directive.session_id == "sess_abc123"
    end

    test "creates directive with model" do
      directive =
        AgentSession.new!(%{
          id: "dir_789",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Test task",
          model: "claude-sonnet-4-5-20250929"
        })

      assert directive.model == "claude-sonnet-4-5-20250929"
    end

    test "creates directive with custom timeout" do
      directive =
        AgentSession.new!(%{
          id: "dir_timeout",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Long task",
          timeout: 600_000
        })

      assert directive.timeout == 600_000
    end

    test "creates directive with max_turns" do
      directive =
        AgentSession.new!(%{
          id: "dir_turns",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Limited task",
          max_turns: 10
        })

      assert directive.max_turns == 10
    end

    test "creates directive with emit_events disabled" do
      directive =
        AgentSession.new!(%{
          id: "dir_quiet",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Silent task",
          emit_events: false
        })

      assert directive.emit_events == false
    end

    test "creates directive with session_config" do
      config = %{
        allowed_tools: ["read", "write", "bash"],
        working_directory: "/path/to/project",
        system_prompt: "You are a senior Elixir developer."
      }

      directive =
        AgentSession.new!(%{
          id: "dir_config",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Task with config",
          session_config: config
        })

      assert directive.session_config == config
    end

    test "creates directive with metadata" do
      directive =
        AgentSession.new!(%{
          id: "dir_meta",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Tracked task",
          metadata: %{user_id: "user_42", priority: :high}
        })

      assert directive.metadata == %{user_id: "user_42", priority: :high}
    end

    test "creates directive with all optional fields" do
      directive =
        AgentSession.new!(%{
          id: "dir_full",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Full task",
          session_id: "sess_existing",
          session_config: %{working_directory: "/tmp"},
          model: "claude-sonnet-4-5-20250929",
          timeout: 600_000,
          max_turns: 20,
          emit_events: true,
          metadata: %{trace_id: "abc"}
        })

      assert directive.id == "dir_full"
      assert directive.adapter == AgentSessionManager.Adapters.ClaudeAdapter
      assert directive.input == "Full task"
      assert directive.session_id == "sess_existing"
      assert directive.session_config == %{working_directory: "/tmp"}
      assert directive.model == "claude-sonnet-4-5-20250929"
      assert directive.timeout == 600_000
      assert directive.max_turns == 20
      assert directive.emit_events == true
      assert directive.metadata == %{trace_id: "abc"}
    end

    test "raises on missing required fields - id" do
      assert_raise RuntimeError, ~r/Invalid AgentSession/, fn ->
        AgentSession.new!(%{
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          input: "Missing id"
        })
      end
    end

    test "raises on missing required fields - adapter" do
      assert_raise RuntimeError, ~r/Invalid AgentSession/, fn ->
        AgentSession.new!(%{
          id: "dir_bad",
          input: "Missing adapter"
        })
      end
    end

    test "raises on missing required fields - input" do
      assert_raise RuntimeError, ~r/Invalid AgentSession/, fn ->
        AgentSession.new!(%{
          id: "dir_bad",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter
        })
      end
    end
  end
end
