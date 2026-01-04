defmodule Jido.AI.ReAct.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReAct.Machine

  # ============================================================================
  # Machine Creation
  # ============================================================================

  describe "new/0" do
    test "creates machine in idle state" do
      machine = Machine.new()
      assert machine.status == "idle"
      assert machine.iteration == 0
      assert machine.conversation == []
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

      {machine, directives} = Machine.update(machine, {:start, "Hello", "call_123"}, env)

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

    test "sets up conversation with system and user messages" do
      machine = Machine.new()
      env = %{system_prompt: "Be helpful", max_iterations: 10}

      {machine, _directives} = Machine.update(machine, {:start, "What is 2+2?", "call_123"}, env)

      assert length(machine.conversation) == 2
      [system_msg, user_msg] = machine.conversation
      assert system_msg.content == "Be helpful"
      assert user_msg.content == "What is 2+2?"
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
        conversation: [],
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{
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
        conversation: [],
        usage: %{input_tokens: 50, output_tokens: 25},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{
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
        conversation: [],
        usage: %{input_tokens: 50},
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{
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
        started_at: 12345
      }

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.usage == %{input_tokens: 100, output_tokens: 50}
      assert restored.started_at == 12345
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
        conversation: [],
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
        conversation: [],
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
        conversation: [],
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
end
