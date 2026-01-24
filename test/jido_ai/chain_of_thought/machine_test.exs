defmodule Jido.AI.ChainOfThought.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ChainOfThought.Machine

  # ============================================================================
  # Machine Creation
  # ============================================================================

  describe "new/0" do
    test "creates machine in idle state" do
      machine = Machine.new()
      assert machine.status == "idle"
      assert machine.prompt == nil
      assert machine.steps == []
      assert machine.conclusion == nil
      assert machine.usage == %{}
      assert machine.started_at == nil
    end
  end

  # ============================================================================
  # Start Transition
  # ============================================================================

  describe "update/3 with :start message" do
    test "transitions from idle to reasoning" do
      machine = Machine.new()
      env = %{system_prompt: "Think step by step."}

      {machine, _directives} = Machine.update(machine, {:start, "What is 2+2?", "cot_123"}, env)

      assert machine.status == "reasoning"
      assert machine.prompt == "What is 2+2?"
      assert machine.current_call_id == "cot_123"
    end

    test "initializes usage and started_at" do
      machine = Machine.new()
      env = %{system_prompt: "Think step by step."}

      before = System.monotonic_time(:millisecond)
      {machine, _directives} = Machine.update(machine, {:start, "Test", "cot_123"}, env)
      after_time = System.monotonic_time(:millisecond)

      assert machine.usage == %{}
      assert is_integer(machine.started_at)
      assert machine.started_at >= before
      assert machine.started_at <= after_time
    end

    test "returns call_llm_stream directive" do
      machine = Machine.new()
      env = %{system_prompt: "Think step by step."}

      {_machine, directives} = Machine.update(machine, {:start, "What is 2+2?", "cot_123"}, env)

      assert [{:call_llm_stream, "cot_123", conversation}] = directives
      assert length(conversation) == 2
      assert Enum.at(conversation, 0).role == :system
      assert Enum.at(conversation, 1).role == :user
      assert Enum.at(conversation, 1).content == "What is 2+2?"
    end

    test "uses default system prompt if not provided" do
      machine = Machine.new()
      env = %{}

      {_machine, directives} = Machine.update(machine, {:start, "Test", "cot_123"}, env)

      [{:call_llm_stream, _, conversation}] = directives
      system_msg = Enum.at(conversation, 0)
      assert system_msg.content =~ "step by step"
    end
  end

  # ============================================================================
  # LLM Result Handling
  # ============================================================================

  describe "update/3 with :llm_result message" do
    test "transitions to completed on success" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{text: "Step 1: Add the numbers.\nConclusion: 4"}}

      {machine, _directives} = Machine.update(machine, {:llm_result, "cot_123", result}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :success
    end

    test "extracts steps and conclusion from response" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        started_at: System.monotonic_time(:millisecond)
      }

      result =
        {:ok,
         %{
           text: """
           Step 1: First, we identify the numbers: 2 and 2.
           Step 2: We add them together: 2 + 2 = 4.
           Conclusion: The answer is 4.
           """
         }}

      {machine, _directives} = Machine.update(machine, {:llm_result, "cot_123", result}, %{})

      assert length(machine.steps) == 2
      assert Enum.at(machine.steps, 0).number == 1
      assert Enum.at(machine.steps, 0).content =~ "identify the numbers"
      assert Enum.at(machine.steps, 1).number == 2
      assert machine.conclusion =~ "The answer is 4"
    end

    test "accumulates usage from response" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        usage: %{},
        started_at: System.monotonic_time(:millisecond)
      }

      result =
        {:ok,
         %{
           text: "Answer: 4",
           usage: %{input_tokens: 100, output_tokens: 50}
         }}

      {machine, _directives} = Machine.update(machine, {:llm_result, "cot_123", result}, %{})

      assert machine.usage == %{input_tokens: 100, output_tokens: 50}
    end

    test "transitions to error on failure" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:error, :rate_limited}

      {machine, _directives} = Machine.update(machine, {:llm_result, "cot_123", result}, %{})

      assert machine.status == "error"
      assert machine.termination_reason == :error
    end

    test "ignores result from wrong call_id" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        started_at: System.monotonic_time(:millisecond)
      }

      result = {:ok, %{text: "Answer: 4"}}

      {machine, directives} = Machine.update(machine, {:llm_result, "wrong_id", result}, %{})

      assert machine.status == "reasoning"
      assert directives == []
    end
  end

  # ============================================================================
  # Streaming Partial Updates
  # ============================================================================

  describe "update/3 with :llm_partial message" do
    test "accumulates content delta in streaming_text" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        streaming_text: "Hello"
      }

      {machine, _directives} = Machine.update(machine, {:llm_partial, "cot_123", " world", :content}, %{})

      assert machine.streaming_text == "Hello world"
    end

    test "ignores partial from wrong call_id" do
      machine = %Machine{
        status: "reasoning",
        current_call_id: "cot_123",
        streaming_text: "Hello"
      }

      {machine, _directives} = Machine.update(machine, {:llm_partial, "wrong_id", " world", :content}, %{})

      assert machine.streaming_text == "Hello"
    end
  end

  # ============================================================================
  # Step Extraction
  # ============================================================================

  describe "extract_steps_and_conclusion/1" do
    test "extracts numbered steps format (Step N:)" do
      text = """
      Step 1: First, identify the problem.
      Step 2: Break it down into parts.
      Step 3: Solve each part.
      Conclusion: The answer is 42.
      """

      {steps, conclusion} = Machine.extract_steps_and_conclusion(text)

      assert length(steps) == 3
      assert Enum.at(steps, 0).number == 1
      assert Enum.at(steps, 0).content =~ "identify the problem"
      assert Enum.at(steps, 1).number == 2
      assert Enum.at(steps, 2).number == 3
      assert conclusion =~ "The answer is 42"
    end

    test "extracts numbered steps format (N.)" do
      text = """
      1. First step here.
      2. Second step here.
      3. Third step here.
      Answer: Done!
      """

      {steps, conclusion} = Machine.extract_steps_and_conclusion(text)

      assert length(steps) == 3
      assert Enum.at(steps, 0).number == 1
      assert Enum.at(steps, 1).number == 2
      assert Enum.at(steps, 2).number == 3
      assert conclusion =~ "Done!"
    end

    test "extracts bullet point format" do
      text = """
      - First, we do this.
      - Then we do that.
      - Finally, we finish.
      Therefore: Complete.
      """

      {steps, conclusion} = Machine.extract_steps_and_conclusion(text)

      assert length(steps) == 3
      assert Enum.at(steps, 0).content =~ "First, we do this"
      assert conclusion =~ "Complete"
    end

    test "handles various conclusion markers" do
      markers = ["Conclusion:", "Answer:", "Therefore:", "Final Answer:", "Thus:", "Hence:"]

      for marker <- markers do
        text = "Step 1: Do something.\n#{marker} The result."
        {_steps, conclusion} = Machine.extract_steps_and_conclusion(text)
        assert conclusion =~ "The result", "Failed for marker: #{marker}"
      end
    end

    test "handles text without conclusion" do
      text = """
      Step 1: First step.
      Step 2: Second step.
      """

      {steps, conclusion} = Machine.extract_steps_and_conclusion(text)

      assert length(steps) == 2
      assert conclusion == nil
    end

    test "handles text without steps" do
      text = "The answer is simply 42."

      {steps, conclusion} = Machine.extract_steps_and_conclusion(text)

      assert steps == []
      assert conclusion == nil
    end

    test "handles empty or nil input" do
      assert {[], nil} = Machine.extract_steps_and_conclusion("")
      assert {[], nil} = Machine.extract_steps_and_conclusion(nil)
    end
  end

  # ============================================================================
  # to_map/from_map
  # ============================================================================

  describe "to_map/1 and from_map/1" do
    test "round-trips machine state" do
      machine = %Machine{
        status: "completed",
        prompt: "What is 2+2?",
        steps: [%{number: 1, content: "Add numbers"}],
        conclusion: "4",
        usage: %{input_tokens: 100},
        started_at: 12_345
      }

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.status == "completed"
      assert restored.prompt == "What is 2+2?"
      assert restored.steps == [%{number: 1, content: "Add numbers"}]
      assert restored.conclusion == "4"
      assert restored.usage == %{input_tokens: 100}
      assert restored.started_at == 12_345
    end

    test "converts status to atom in to_map" do
      machine = %Machine{status: "reasoning"}
      map = Machine.to_map(machine)

      assert map.status == :reasoning
    end

    test "from_map handles atom status" do
      map = %{status: :completed}
      machine = Machine.from_map(map)

      assert machine.status == "completed"
    end
  end

  # ============================================================================
  # Generate Call ID
  # ============================================================================

  describe "generate_call_id/0" do
    test "generates unique call IDs with cot_ prefix" do
      id1 = Machine.generate_call_id()
      id2 = Machine.generate_call_id()

      assert String.starts_with?(id1, "cot_")
      assert String.starts_with?(id2, "cot_")
      assert id1 != id2
    end
  end

  # ============================================================================
  # Default System Prompt
  # ============================================================================

  describe "default_system_prompt/0" do
    test "returns a prompt encouraging step-by-step thinking" do
      prompt = Machine.default_system_prompt()

      assert is_binary(prompt)
      assert prompt =~ "step"
      assert prompt =~ "Conclusion" or prompt =~ "Answer"
    end
  end
end
