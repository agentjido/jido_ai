defmodule Jido.AI.Signal.AgentSessionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Signal.AgentSession

  describe "Started" do
    test "creates signal with required fields" do
      signal =
        AgentSession.Started.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456"
        })

      assert signal.type == "ai.agent_session.started"
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.run_id == "run_def456"
      assert signal.data.metadata == %{}
    end

    test "creates signal with all optional fields" do
      signal =
        AgentSession.Started.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          directive_id: "dir_ghi789",
          adapter: AgentSessionManager.Adapters.ClaudeAdapter,
          model: "claude-sonnet-4-5-20250929",
          input: "Refactor the auth module",
          metadata: %{user_id: "user_42"}
        })

      assert signal.data.directive_id == "dir_ghi789"
      assert signal.data.adapter == AgentSessionManager.Adapters.ClaudeAdapter
      assert signal.data.model == "claude-sonnet-4-5-20250929"
      assert signal.data.input == "Refactor the auth module"
      assert signal.data.metadata == %{user_id: "user_42"}
    end

    test "creates signal via new/1 returning ok tuple" do
      assert {:ok, signal} =
               AgentSession.Started.new(%{
                 session_id: "sess_1",
                 run_id: "run_1"
               })

      assert signal.type == "ai.agent_session.started"
    end
  end

  describe "Message" do
    test "creates signal with required fields" do
      signal =
        AgentSession.Message.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          content: "I'll start by reading the auth module..."
        })

      assert signal.type == "ai.agent_session.message"
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.run_id == "run_def456"
      assert signal.data.content == "I'll start by reading the auth module..."
      assert signal.data.role == :assistant
      assert signal.data.delta == false
    end

    test "creates streaming delta message" do
      signal =
        AgentSession.Message.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          content: "Hello",
          delta: true
        })

      assert signal.data.delta == true
    end

    test "creates message with system role" do
      signal =
        AgentSession.Message.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          content: "System notice",
          role: :system
        })

      assert signal.data.role == :system
    end

    test "accumulates streaming deltas" do
      chunks = ["Hello", ", ", "world", "!"]

      signals =
        Enum.map(chunks, fn chunk ->
          AgentSession.Message.new!(%{
            session_id: "sess_1",
            run_id: "run_1",
            content: chunk,
            delta: true
          })
        end)

      assert length(signals) == 4
      assert Enum.all?(signals, &(&1.type == "ai.agent_session.message"))

      accumulated = signals |> Enum.map_join(& &1.data.content)
      assert accumulated == "Hello, world!"
    end
  end

  describe "ToolCall" do
    test "creates started tool call signal" do
      signal =
        AgentSession.ToolCall.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          tool_name: "read_file",
          status: :started
        })

      assert signal.type == "ai.agent_session.tool_call"
      assert signal.data.tool_name == "read_file"
      assert signal.data.status == :started
      assert signal.data.tool_input == %{}
    end

    test "creates tool call with input and tool_id" do
      signal =
        AgentSession.ToolCall.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          tool_name: "write_file",
          tool_input: %{path: "lib/auth.ex", content: "defmodule Auth do..."},
          tool_id: "tc_xyz",
          status: :started
        })

      assert signal.data.tool_input == %{path: "lib/auth.ex", content: "defmodule Auth do..."}
      assert signal.data.tool_id == "tc_xyz"
    end

    test "supports all status values" do
      statuses = [:started, :completed, :failed]

      for status <- statuses do
        signal =
          AgentSession.ToolCall.new!(%{
            session_id: "sess_1",
            run_id: "run_1",
            tool_name: "test_tool",
            status: status
          })

        assert signal.data.status == status
      end
    end
  end

  describe "Progress" do
    test "creates progress signal with required fields" do
      signal =
        AgentSession.Progress.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456"
        })

      assert signal.type == "ai.agent_session.progress"
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.run_id == "run_def456"
      assert signal.data.tokens_used == %{}
    end

    test "creates progress signal with turn information" do
      signal =
        AgentSession.Progress.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          turn: 5,
          max_turns: 20,
          tokens_used: %{input: 12500, output: 3200}
        })

      assert signal.data.turn == 5
      assert signal.data.max_turns == 20
      assert signal.data.tokens_used == %{input: 12500, output: 3200}
    end
  end

  describe "Completed" do
    test "creates completed signal with required fields" do
      signal =
        AgentSession.Completed.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          output: "I've refactored the auth module to use JWT."
        })

      assert signal.type == "ai.agent_session.completed"
      assert signal.data.output == "I've refactored the auth module to use JWT."
      assert signal.data.token_usage == %{}
      assert signal.data.metadata == %{}
    end

    test "creates completed signal with all fields" do
      signal =
        AgentSession.Completed.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          directive_id: "dir_ghi789",
          output: "Refactoring complete.",
          token_usage: %{input_tokens: 45000, output_tokens: 12000},
          duration_ms: 47000,
          metadata: %{files_changed: 3}
        })

      assert signal.data.directive_id == "dir_ghi789"
      assert signal.data.token_usage == %{input_tokens: 45000, output_tokens: 12000}
      assert signal.data.duration_ms == 47000
      assert signal.data.metadata == %{files_changed: 3}
    end
  end

  describe "Failed" do
    test "creates failed signal with required fields" do
      signal =
        AgentSession.Failed.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          reason: :timeout
        })

      assert signal.type == "ai.agent_session.failed"
      assert signal.data.reason == :timeout
      assert signal.data.token_usage == %{}
      assert signal.data.metadata == %{}
    end

    test "creates failed signal with all fields" do
      signal =
        AgentSession.Failed.new!(%{
          session_id: "sess_abc123",
          run_id: "run_def456",
          directive_id: "dir_ghi789",
          reason: :error,
          error_message: "API rate limit exceeded",
          partial_output: "I started refactoring but...",
          token_usage: %{input_tokens: 30000, output_tokens: 8000},
          metadata: %{retry_count: 2}
        })

      assert signal.data.directive_id == "dir_ghi789"
      assert signal.data.reason == :error
      assert signal.data.error_message == "API rate limit exceeded"
      assert signal.data.partial_output == "I started refactoring but..."
      assert signal.data.token_usage == %{input_tokens: 30000, output_tokens: 8000}
      assert signal.data.metadata == %{retry_count: 2}
    end

    test "supports all reason values" do
      reasons = [:timeout, :cancelled, :error]

      for reason <- reasons do
        signal =
          AgentSession.Failed.new!(%{
            session_id: "sess_1",
            run_id: "run_1",
            reason: reason
          })

        assert signal.data.reason == reason
      end
    end
  end

  describe "from_event/2" do
    setup do
      context = %{
        session_id: "sess_abc123",
        run_id: "run_def456",
        directive_id: "dir_ghi789",
        metadata: %{user_id: "user_42"}
      }

      {:ok, context: context}
    end

    test "maps :run_started event to Started signal", %{context: context} do
      event = %{type: :run_started, data: %{}, session_id: "sess_abc123", run_id: "run_def456"}

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.started"
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.run_id == "run_def456"
      assert signal.data.directive_id == "dir_ghi789"
    end

    test "maps :message_received event to Message signal (delta: false)", %{context: context} do
      event = %{
        type: :message_received,
        data: %{content: "Hello, world!"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.message"
      assert signal.data.content == "Hello, world!"
      assert signal.data.delta == false
    end

    test "maps :message_streamed event to Message signal (delta: true)", %{context: context} do
      event = %{
        type: :message_streamed,
        data: %{delta: "Hello"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.message"
      assert signal.data.content == "Hello"
      assert signal.data.delta == true
    end

    test "maps :message_streamed with content key", %{context: context} do
      event = %{
        type: :message_streamed,
        data: %{content: "chunk"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.data.content == "chunk"
      assert signal.data.delta == true
    end

    test "maps :tool_call_started event to ToolCall signal", %{context: context} do
      event = %{
        type: :tool_call_started,
        data: %{tool_name: "read_file", tool_input: %{path: "lib/auth.ex"}, tool_id: "tc_1"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.tool_call"
      assert signal.data.tool_name == "read_file"
      assert signal.data.tool_input == %{path: "lib/auth.ex"}
      assert signal.data.tool_id == "tc_1"
      assert signal.data.status == :started
    end

    test "maps :tool_call_completed event to ToolCall signal", %{context: context} do
      event = %{
        type: :tool_call_completed,
        data: %{tool_name: "read_file", tool_id: "tc_1"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.data.status == :completed
    end

    test "maps :tool_call_failed event to ToolCall signal", %{context: context} do
      event = %{
        type: :tool_call_failed,
        data: %{tool_name: "write_file", tool_id: "tc_2"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.data.status == :failed
    end

    test "maps :run_completed event to Completed signal", %{context: context} do
      event = %{
        type: :run_completed,
        data: %{},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.completed"
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.directive_id == "dir_ghi789"
    end

    test "maps :run_failed event to Failed signal", %{context: context} do
      event = %{
        type: :run_failed,
        data: %{},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.failed"
      assert signal.data.reason == :error
    end

    test "maps :run_cancelled event to Failed signal with reason :cancelled", %{context: context} do
      event = %{
        type: :run_cancelled,
        data: %{},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.failed"
      assert signal.data.reason == :cancelled
    end

    test "maps :token_usage_updated to Progress signal", %{context: context} do
      event = %{
        type: :token_usage_updated,
        data: %{input_tokens: 500, output_tokens: 200},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.progress"
      assert signal.data.tokens_used == %{input_tokens: 500, output_tokens: 200}
    end

    test "maps unknown event type to Progress signal", %{context: context} do
      event = %{
        type: :some_unknown_event,
        data: %{foo: "bar"},
        session_id: "sess_abc123",
        run_id: "run_def456"
      }

      signal = AgentSession.from_event(event, context)

      assert signal.type == "ai.agent_session.progress"
    end
  end

  describe "completed/2" do
    test "builds Completed signal from run result" do
      run_result = %{
        output: "Refactoring complete.",
        token_usage: %{input_tokens: 45000, output_tokens: 12000},
        events: []
      }

      context = %{
        session_id: "sess_abc123",
        run_id: "run_def456",
        directive_id: "dir_ghi789",
        metadata: %{}
      }

      signal = AgentSession.completed(run_result, context)

      assert signal.type == "ai.agent_session.completed"
      assert signal.data.output == "Refactoring complete."
      assert signal.data.token_usage == %{input_tokens: 45000, output_tokens: 12000}
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.run_id == "run_def456"
      assert signal.data.directive_id == "dir_ghi789"
    end
  end

  describe "failed/2" do
    test "builds Failed signal from error" do
      error = %{message: "Timeout exceeded", class: :timeout}

      context = %{
        session_id: "sess_abc123",
        run_id: "run_def456",
        directive_id: "dir_ghi789",
        metadata: %{}
      }

      signal = AgentSession.failed(error, context)

      assert signal.type == "ai.agent_session.failed"
      assert signal.data.reason == :error
      assert signal.data.session_id == "sess_abc123"
      assert signal.data.directive_id == "dir_ghi789"
    end

    test "extracts error message from string error" do
      signal =
        AgentSession.failed("something went wrong", %{
          session_id: "sess_1",
          run_id: "run_1",
          directive_id: "dir_1",
          metadata: %{}
        })

      assert signal.data.error_message == "something went wrong"
    end
  end
end
