defmodule Jido.AI.ReAct.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReAct.Machine
  alias Jido.AI.Thread

  # Helper to create a thread with a system prompt and optional messages
  defp make_thread(system_prompt, messages \\ []) do
    thread = Thread.new(system_prompt: system_prompt)
    Thread.append_messages(thread, messages)
  end

  # ============================================================================
  # Machine Creation
  # ============================================================================

  describe "new/0" do
    test "creates machine in idle state" do
      machine = Machine.new()
      assert machine.status == "idle"
      assert machine.iteration == 0
      assert machine.thread == nil
      assert machine.usage == %{}
      assert machine.started_at == nil
    end
  end

  # ============================================================================
  # Start Transition
  # ============================================================================

  describe "update/3 with :start message" do
    test "transitions from idle to awaiting_llm" do
      machine = Machine.new()
      env = %{system_prompt: "You are helpful.", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)

      assert machine.status == "awaiting_llm"
      assert machine.iteration == 1
      assert machine.current_llm_call_id == "call_123"
    end

    test "initializes usage as empty map on start" do
      machine = Machine.new()
      env = %{system_prompt: "You are helpful.", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)

      assert machine.usage == %{}
    end

    test "sets started_at timestamp on start" do
      machine = Machine.new()
      env = %{system_prompt: "You are helpful.", max_iterations: 10}

      before = System.monotonic_time(:millisecond)
      {machine, _directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)
      after_time = System.monotonic_time(:millisecond)

      assert is_integer(machine.started_at)
      # started_at should be between before and after
      assert machine.started_at >= before
      assert machine.started_at <= after_time
    end

    test "returns call_llm_stream directive" do
      machine = Machine.new()
      env = %{system_prompt: "You are helpful.", max_iterations: 10}

      {_machine, directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)

      assert [{:call_llm_stream, "call_123", conversation}] = directives
      assert length(conversation) == 2
      assert Enum.at(conversation, 0).role == :system
      assert Enum.at(conversation, 1).role == :user
    end

    test "sets up thread with system prompt and user message" do
      machine = Machine.new()
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:start, "What is 2+2?", "call_123"}, env)

      assert machine.thread != nil
      assert machine.thread.system_prompt == "Be helpful"
      assert Thread.length(machine.thread) == 1
      [user_entry] = machine.thread.entries
      assert user_entry.role == :user
      assert user_entry.content == "What is 2+2?"
    end
  end

  # ============================================================================
  # Usage Metadata Accumulation
  # ============================================================================

  describe "usage accumulation" do
    test "accumulates usage from LLM result" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result =
        {:ok,
         %{
           type: :final_answer,
           text: "The answer is 4.",
           usage: %{input_tokens: 100, output_tokens: 50}
         }}

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert machine.usage == %{input_tokens: 100, output_tokens: 50}
    end

    test "accumulates usage across multiple LLM calls" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        usage: %{input_tokens: 50, output_tokens: 25},
        started_at: System.monotonic_time(:millisecond)
      }

      result =
        {:ok,
         %{
           type: :final_answer,
           text: "Done.",
           usage: %{input_tokens: 100, output_tokens: 50}
         }}

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      # Should be accumulated
      assert machine.usage == %{input_tokens: 150, output_tokens: 75}
    end

    test "handles LLM result without usage field" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        usage: %{input_tokens: 50},
        started_at: System.monotonic_time(:millisecond)
      }

      result =
        {:ok,
         %{
           type: :final_answer,
           text: "Done."
           # no usage field
         }}

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      # Should preserve existing usage
      assert machine.usage == %{input_tokens: 50}
    end
  end

  # ============================================================================
  # to_map/from_map
  # ============================================================================

  describe "to_map/1 and from_map/1" do
    test "round-trips machine state including usage" do
      machine = %Machine{
        status: "awaiting_llm",
        iteration: 3,
        usage: %{input_tokens: 100, output_tokens: 50},
        started_at: 12_345
      }

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.usage == %{input_tokens: 100, output_tokens: 50}
      assert restored.started_at == 12_345
    end

    test "converts status to atom in to_map" do
      machine = %Machine{status: "awaiting_llm"}
      map = Machine.to_map(machine)

      assert map.status == :awaiting_llm
    end

    test "from_map handles atom status" do
      map = %{status: :awaiting_llm, iteration: 1}
      machine = Machine.from_map(map)

      assert machine.status == "awaiting_llm"
    end

    test "from_map defaults usage to empty map" do
      map = %{status: :idle}
      machine = Machine.from_map(map)

      assert machine.usage == %{}
    end
  end

  # ============================================================================
  # Final Answer Handling
  # ============================================================================

  describe "final answer" do
    test "transitions to completed on final answer" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{type: :final_answer, text: "The answer is 42."}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert machine.status == "completed"
      assert machine.termination_reason == :final_answer
      assert machine.result == "The answer is 42."
      assert directives == []
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  describe "error handling" do
    test "transitions to error on LLM error" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:error, :rate_limited}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert machine.status == "error"
      assert machine.termination_reason == :error
      assert directives == []
    end
  end

  # ============================================================================
  # Max Iterations
  # ============================================================================

  describe "max iterations" do
    test "terminates when max iterations exceeded" do
      machine = %Machine{
        status: "awaiting_tool",
        iteration: 10,
        thread: make_thread("Be helpful"),
        pending_tool_calls: [%{id: "tc_1", name: "calc", arguments: %{}, result: nil}],
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:tool_result, "tc_1", {:ok, %{}}}, env)

      # After recording tool result and incrementing iteration to 11, it should complete
      assert machine.status == "completed"
      assert machine.termination_reason == :max_iterations
    end
  end

  # ============================================================================
  # Streaming Partial Updates
  # ============================================================================

  describe "streaming partial updates" do
    test "accumulates content delta in streaming_text" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        streaming_text: "Hello",
        streaming_thinking: ""
      }

      env = %{}

      {machine, _directives} = Machine.update(machine, {:llm_partial, "call_123", " world", :content}, env)

      assert machine.streaming_text == "Hello world"
    end

    test "accumulates thinking delta in streaming_thinking" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        streaming_text: "",
        streaming_thinking: "Let me think"
      }

      env = %{}

      {machine, _directives} = Machine.update(machine, {:llm_partial, "call_123", "...", :thinking}, env)

      assert machine.streaming_thinking == "Let me think..."
    end

    test "ignores partial from different call_id" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        streaming_text: "Hello"
      }

      env = %{}

      {machine, _directives} = Machine.update(machine, {:llm_partial, "call_wrong", " world", :content}, env)

      assert machine.streaming_text == "Hello"
    end
  end

  # ============================================================================
  # Telemetry Emission
  # ============================================================================

  describe "telemetry emission" do
    test "emits iteration telemetry when continuing to next iteration" do
      # Attach a telemetry handler to capture the event
      ref = make_ref()
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end

      :telemetry.attach(
        "test-iteration-handler-#{inspect(ref)}",
        [:jido, :ai, :react, :iteration],
        handler,
        nil
      )

      # Set up a machine that will transition to next iteration (after tool result)
      thread =
        make_thread("Be helpful", [
          %{role: :user, content: "Test"}
        ])

      machine = %Machine{
        status: "awaiting_tool",
        iteration: 1,
        thread: thread,
        pending_tool_calls: [%{id: "tc_1", name: "calc", arguments: %{}, result: nil}],
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      # Process tool result - this should trigger next iteration and emit telemetry
      {_machine, _directives} = Machine.update(machine, {:tool_result, "tc_1", {:ok, %{result: 42}}}, env)

      # Verify telemetry was emitted
      assert_receive {:telemetry_event, ^ref, [:jido, :ai, :react, :iteration], measurements, metadata}, 1000

      assert is_map(measurements)
      assert Map.has_key?(measurements, :system_time)
      assert metadata.iteration == 2
      assert String.starts_with?(metadata.call_id, "call_")

      # Cleanup
      :telemetry.detach("test-iteration-handler-#{inspect(ref)}")
    end

    test "emits start telemetry on start" do
      ref = make_ref()
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end

      :telemetry.attach(
        "test-start-handler-#{inspect(ref)}",
        [:jido, :ai, :react, :start],
        handler,
        nil
      )

      machine = Machine.new()
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {_machine, _directives} = Machine.update(machine, {:start, "Hello world", "call_123"}, env)

      # Should emit start telemetry
      assert_receive {:telemetry_event, ^ref, [:jido, :ai, :react, :start], measurements, metadata}, 1000

      assert Map.has_key?(measurements, :system_time)
      assert metadata.call_id == "call_123"
      # "Hello world" length
      assert metadata.query_length == 11

      :telemetry.detach("test-start-handler-#{inspect(ref)}")
    end
  end

  # ============================================================================
  # Generate Call ID
  # ============================================================================

  describe "generate_call_id/0" do
    test "generates unique call IDs" do
      id1 = Machine.generate_call_id()
      id2 = Machine.generate_call_id()

      assert String.starts_with?(id1, "call_")
      assert String.starts_with?(id2, "call_")
      assert id1 != id2
    end
  end

  # ============================================================================
  # Issue #3 Fix: Busy State Handling (Explicit Rejection)
  # ============================================================================

  describe "busy state handling - Issue #3 fix" do
    test "rejects start request when in awaiting_llm state with request_error directive" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        iteration: 1
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {result_machine, directives} = Machine.update(machine, {:start, "New query", "call_456"}, env)

      # Machine state should be unchanged
      assert result_machine.status == "awaiting_llm"
      assert result_machine.current_llm_call_id == "call_123"

      # Should return a request_error directive
      assert [{:request_error, "call_456", :busy, message}] = directives
      assert message =~ "awaiting_llm"
    end

    test "rejects start request when in awaiting_tool state with request_error directive" do
      machine = %Machine{
        status: "awaiting_tool",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        iteration: 1,
        pending_tool_calls: [%{id: "tc_1", name: "calc", arguments: %{}, result: nil}]
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {result_machine, directives} = Machine.update(machine, {:start, "New query", "call_456"}, env)

      # Machine state should be unchanged
      assert result_machine.status == "awaiting_tool"
      assert result_machine.pending_tool_calls == machine.pending_tool_calls

      # Should return a request_error directive
      assert [{:request_error, "call_456", :busy, message}] = directives
      assert message =~ "awaiting_tool"
    end

    test "allows start request from idle state" do
      machine = Machine.new()
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {result_machine, directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)

      assert result_machine.status == "awaiting_llm"
      assert [{:call_llm_stream, "call_123", _messages}] = directives
    end

    test "allows start request from completed state (continuation)" do
      thread =
        make_thread("Be helpful", [
          %{role: :user, content: "Hello"},
          %{role: :assistant, content: "Hi there!"}
        ])

      machine = %Machine{
        status: "completed",
        thread: thread,
        result: "Hi there!",
        termination_reason: :final_answer
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {result_machine, directives} = Machine.update(machine, {:start, "Follow up", "call_456"}, env)

      assert result_machine.status == "awaiting_llm"
      assert [{:call_llm_stream, "call_456", messages}] = directives
      # Messages should include system + original entries + new user message
      assert length(messages) == 4
    end

    test "allows start request from error state (recovery)" do
      thread =
        make_thread("Be helpful", [
          %{role: :user, content: "Hello"}
        ])

      machine = %Machine{
        status: "error",
        thread: thread,
        result: "Error: something went wrong",
        termination_reason: :error
      }

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {result_machine, directives} = Machine.update(machine, {:start, "Try again", "call_789"}, env)

      assert result_machine.status == "awaiting_llm"
      assert [{:call_llm_stream, "call_789", _messages}] = directives
    end
  end

  # ============================================================================
  # Thinking Trace
  # ============================================================================

  describe "thinking_trace" do
    test "starts with empty thinking_trace" do
      machine = Machine.new()
      assert machine.thinking_trace == []
    end

    test "captures streaming_thinking into trace on final answer" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "I need to think about this carefully",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "The answer is 42."}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert machine.status == "completed"
      assert length(machine.thinking_trace) == 1
      [entry] = machine.thinking_trace
      assert entry.call_id == "call_123"
      assert entry.iteration == 1
      assert entry.thinking == "I need to think about this carefully"
    end

    test "captures thinking from classified result when streaming_thinking is empty" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "Done.", thinking_content: "Classified thinking here"}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert length(machine.thinking_trace) == 1
      [entry] = machine.thinking_trace
      assert entry.thinking == "Classified thinking here"
    end

    test "prefers streaming_thinking over classified thinking_content" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "Full streaming thinking",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "Done.", thinking_content: "Partial classified"}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      [entry] = machine.thinking_trace
      assert entry.thinking == "Full streaming thinking"
    end

    test "does not create trace entry when no thinking present" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "Done."}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      assert machine.thinking_trace == []
    end

    test "accumulates thinking across iterations" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_1",
        thread: make_thread("Be helpful"),
        streaming_thinking: "Thinking for iteration 1",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      tool_calls_result =
        {:ok,
         %{
           type: :tool_calls,
           text: "",
           tool_calls: [%{id: "tc_1", name: "calc", arguments: %{x: 1}}]
         }}

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} =
        Machine.update(machine, {:llm_result, "call_1", tool_calls_result}, env)

      assert length(machine.thinking_trace) == 1
      assert hd(machine.thinking_trace).thinking == "Thinking for iteration 1"

      # Tool result triggers handle_iteration_check which also captures thinking
      # before resetting streaming_thinking, so iteration 1 thinking appears twice
      {machine, _directives} =
        Machine.update(machine, {:tool_result, "tc_1", {:ok, %{result: 42}}}, env)

      assert length(machine.thinking_trace) == 2

      machine = %{machine | streaming_thinking: "Thinking for iteration 2"}

      second_call_id = machine.current_llm_call_id
      final_result = {:ok, %{type: :final_answer, text: "The answer is 42."}}

      {machine, _directives} =
        Machine.update(machine, {:llm_result, second_call_id, final_result}, env)

      assert length(machine.thinking_trace) == 3
      [first, second, third] = machine.thinking_trace
      assert first.thinking == "Thinking for iteration 1"
      assert second.thinking == "Thinking for iteration 1"
      assert third.thinking == "Thinking for iteration 2"
    end

    test "resets thinking_trace on fresh start" do
      machine = Machine.new()
      machine = %{machine | thinking_trace: [%{call_id: "old", iteration: 1, thinking: "old"}]}

      env = %{system_prompt: "Be helpful", max_iterations: 10}
      {machine, _directives} = Machine.update(machine, {:start, "New query", "call_new"}, env)

      assert machine.thinking_trace == []
    end

    test "round-trips thinking_trace through to_map/from_map" do
      trace = [
        %{call_id: "call_1", iteration: 1, thinking: "First thought"},
        %{call_id: "call_2", iteration: 2, thinking: "Second thought"}
      ]

      machine = %Machine{thinking_trace: trace}
      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.thinking_trace == trace
    end
  end

  # ============================================================================
  # Thinking in Thread
  # ============================================================================

  describe "thinking content in thread" do
    test "stores thinking in thread on final answer" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "Let me reason step by step",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "The answer is 42."}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      messages = Thread.to_messages(machine.thread)
      assistant_msg = List.last(messages)

      assert assistant_msg.role == :assistant
      assert is_list(assistant_msg.content)
      [thinking_block, text_block] = assistant_msg.content
      assert thinking_block == %{type: :thinking, thinking: "Let me reason step by step"}
      assert text_block == %{type: :text, text: "The answer is 42."}
    end

    test "stores thinking in thread on tool calls" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "I need to use a tool",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result =
        {:ok,
         %{
           type: :tool_calls,
           text: "",
           tool_calls: [%{id: "tc_1", name: "calc", arguments: %{x: 1}}]
         }}

      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      messages = Thread.to_messages(machine.thread)
      assistant_msg = List.last(messages)

      assert assistant_msg.role == :assistant
      assert is_list(assistant_msg.content)
      [thinking_block, text_block] = assistant_msg.content
      assert thinking_block == %{type: :thinking, thinking: "I need to use a tool"}
      assert text_block == %{type: :text, text: ""}
    end

    test "does not add thinking blocks when streaming_thinking is empty" do
      machine = %Machine{
        status: "awaiting_llm",
        current_llm_call_id: "call_123",
        thread: make_thread("Be helpful"),
        streaming_thinking: "",
        usage: %{},
        thinking_trace: [],
        started_at: System.monotonic_time(:millisecond),
        iteration: 1
      }

      result = {:ok, %{type: :final_answer, text: "Simple answer."}}
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:llm_result, "call_123", result}, env)

      messages = Thread.to_messages(machine.thread)
      assistant_msg = List.last(messages)

      assert assistant_msg.role == :assistant
      assert assistant_msg.content == "Simple answer."
    end
  end
end
