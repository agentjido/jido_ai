defmodule Jido.AI.TRM.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.TRM.Machine

  describe "new/0" do
    test "creates machine in idle state with default config" do
      machine = Machine.new()

      assert machine.status == "idle"
      assert machine.max_supervision_steps == 5
      assert machine.act_threshold == 0.9
      assert machine.question == nil
      assert machine.current_answer == nil
      assert machine.answer_history == []
      assert machine.supervision_step == 0
      assert machine.act_triggered == false
      assert machine.best_answer == nil
      assert machine.best_score == 0.0
    end
  end

  describe "new/1" do
    test "accepts custom max_supervision_steps" do
      machine = Machine.new(max_supervision_steps: 10)

      assert machine.max_supervision_steps == 10
      assert machine.act_threshold == 0.9
    end

    test "accepts custom act_threshold" do
      machine = Machine.new(act_threshold: 0.85)

      assert machine.act_threshold == 0.85
      assert machine.max_supervision_steps == 5
    end

    test "accepts both options" do
      machine = Machine.new(max_supervision_steps: 3, act_threshold: 0.95)

      assert machine.max_supervision_steps == 3
      assert machine.act_threshold == 0.95
    end
  end

  describe "update/3 with :start message" do
    test "transitions from idle to reasoning" do
      machine = Machine.new()
      call_id = "trm_test_123"

      {machine, directives} = Machine.update(machine, {:start, "What is 2+2?", call_id})

      assert machine.status == "reasoning"
      assert machine.question == "What is 2+2?"
      assert machine.supervision_step == 1
      assert machine.current_call_id == call_id
      assert machine.started_at != nil
    end

    test "returns reasoning directive" do
      machine = Machine.new()
      call_id = "trm_test_123"

      {_machine, directives} = Machine.update(machine, {:start, "What is 2+2?", call_id})

      assert length(directives) == 1
      assert {:reason, ^call_id, context} = hd(directives)
      assert context.question == "What is 2+2?"
      assert context.step == 1
    end

    test "initializes latent state" do
      machine = Machine.new()
      call_id = "trm_test_123"

      {machine, _directives} = Machine.update(machine, {:start, "What is 2+2?", call_id})

      assert machine.latent_state.question_context == "What is 2+2?"
      assert machine.latent_state.reasoning_trace == []
      assert machine.latent_state.confidence_score == 0.0
    end

    test "ignores start when not in idle state" do
      machine = %{Machine.new() | status: "reasoning"}

      {machine, directives} = Machine.update(machine, {:start, "New question", "call_2"})

      assert machine.status == "reasoning"
      assert directives == []
    end
  end

  describe "update/3 with :reasoning_result message" do
    setup do
      machine = Machine.new()
      call_id = "trm_test_123"
      {machine, _} = Machine.update(machine, {:start, "What is 2+2?", call_id})
      {:ok, machine: machine, call_id: call_id}
    end

    test "transitions to supervising on success", %{machine: machine, call_id: call_id} do
      result = {:ok, %{text: "The answer is 4 because 2+2=4"}}

      {machine, directives} = Machine.update(machine, {:reasoning_result, call_id, result})

      assert machine.status == "supervising"
      assert machine.current_answer == "The answer is 4 because 2+2=4"
    end

    test "returns supervise directive", %{machine: machine, call_id: call_id} do
      result = {:ok, %{text: "The answer is 4"}}

      {machine, directives} = Machine.update(machine, {:reasoning_result, call_id, result})

      assert length(directives) == 1
      {:supervise, new_call_id, context} = hd(directives)
      assert new_call_id != call_id
      assert context.question == "What is 2+2?"
      assert context.current_answer == "The answer is 4"
    end

    test "updates latent state with reasoning trace", %{machine: machine, call_id: call_id} do
      result = {:ok, %{text: "Let me think about this"}}

      {machine, _directives} = Machine.update(machine, {:reasoning_result, call_id, result})

      assert length(machine.latent_state.reasoning_trace) == 1
      assert hd(machine.latent_state.reasoning_trace) =~ "[reasoning]"
    end

    test "transitions to error on failure", %{machine: machine, call_id: call_id} do
      result = {:error, :timeout}

      {machine, directives} = Machine.update(machine, {:reasoning_result, call_id, result})

      assert machine.status == "error"
      assert machine.termination_reason == :error
      assert directives == []
    end

    test "ignores result with wrong call_id", %{machine: machine} do
      result = {:ok, %{text: "Answer"}}

      {machine, directives} = Machine.update(machine, {:reasoning_result, "wrong_id", result})

      assert machine.status == "reasoning"
      assert directives == []
    end

    test "accumulates usage metadata", %{machine: machine, call_id: call_id} do
      result = {:ok, %{text: "Answer", usage: %{input_tokens: 100, output_tokens: 50}}}

      {machine, _directives} = Machine.update(machine, {:reasoning_result, call_id, result})

      assert machine.usage.input_tokens == 100
      assert machine.usage.output_tokens == 50
    end
  end

  describe "update/3 with :supervision_result message" do
    setup do
      machine = Machine.new()
      call_id = "trm_test_123"
      {machine, _} = Machine.update(machine, {:start, "What is 2+2?", call_id})
      {machine, _} = Machine.update(machine, {:reasoning_result, call_id, {:ok, %{text: "4"}}})
      {:ok, machine: machine}
    end

    test "transitions to improving on success", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "Score: 0.7. The answer is correct but lacks explanation."}}

      {machine, directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert machine.status == "improving"
      assert machine.supervision_feedback =~ "Score: 0.7"
    end

    test "returns improve directive", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "The answer needs more detail"}}

      {machine, directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert length(directives) == 1
      {:improve, new_call_id, context} = hd(directives)
      assert new_call_id != call_id
      assert context.feedback == "The answer needs more detail"
    end

    test "updates best answer when score improves", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "Score: 0.8. Good answer."}}

      {machine, _directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert machine.best_answer == "4"
      assert machine.best_score == 0.8
    end

    test "extracts quality score from feedback", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "SCORE: 0.85. Well done."}}

      {machine, _directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert machine.latent_state.confidence_score == 0.85
    end

    test "defaults to 0.5 when no score in feedback", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "The answer looks reasonable."}}

      {machine, _directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert machine.latent_state.confidence_score == 0.5
    end

    test "transitions to error on failure", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:error, :api_error}

      {machine, directives} = Machine.update(machine, {:supervision_result, call_id, result})

      assert machine.status == "error"
      assert machine.termination_reason == :error
      assert directives == []
    end
  end

  describe "update/3 with :improvement_result message" do
    setup do
      machine = Machine.new(max_supervision_steps: 3)
      call_id = "trm_test_123"
      {machine, _} = Machine.update(machine, {:start, "What is 2+2?", call_id})
      {machine, _} = Machine.update(machine, {:reasoning_result, call_id, {:ok, %{text: "4"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:supervision_result, call_id, {:ok, %{text: "Score: 0.6"}}})
      {:ok, machine: machine}
    end

    test "loops back to reasoning when below threshold", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "The answer is 4 because 2+2 equals 4."}}

      {machine, directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.status == "reasoning"
      assert machine.supervision_step == 2
      assert length(directives) == 1
      {:reason, _, _} = hd(directives)
    end

    test "adds improved answer to history", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "Better answer"}}

      {machine, _directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.answer_history == ["Better answer"]
      assert machine.current_answer == "Better answer"
    end

    test "completes when max_supervision_steps reached", %{machine: machine} do
      # Advance to max steps
      machine = %{machine | supervision_step: 3}
      call_id = machine.current_call_id
      result = {:ok, %{text: "Final answer"}}

      {machine, directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.status == "completed"
      assert machine.termination_reason == :max_steps
      assert directives == []
    end

    test "increments step count in latent state", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:ok, %{text: "Improved"}}

      {machine, _directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.latent_state.step_count == 1
    end

    test "transitions to error on failure", %{machine: machine} do
      call_id = machine.current_call_id
      result = {:error, :rate_limit}

      {machine, directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.status == "error"
      assert machine.termination_reason == :error
      assert directives == []
    end
  end

  describe "ACT early stopping" do
    test "triggers when confidence exceeds threshold" do
      machine = Machine.new(act_threshold: 0.8, max_supervision_steps: 10)

      # Go through the cycle with high confidence supervision
      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})
      {machine, _} = Machine.update(machine, {:reasoning_result, "call_1", {:ok, %{text: "Answer"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:supervision_result, call_id, {:ok, %{text: "Score: 0.85"}}})
      call_id = machine.current_call_id
      result = {:ok, %{text: "Improved answer"}}

      {machine, directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.status == "completed"
      assert machine.termination_reason == :act_threshold
      assert machine.act_triggered == true
      assert directives == []
    end

    test "continues when confidence below threshold" do
      machine = Machine.new(act_threshold: 0.9, max_supervision_steps: 10)

      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})
      {machine, _} = Machine.update(machine, {:reasoning_result, "call_1", {:ok, %{text: "Answer"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:supervision_result, call_id, {:ok, %{text: "Score: 0.7"}}})
      call_id = machine.current_call_id
      result = {:ok, %{text: "Improved answer"}}

      {machine, directives} = Machine.update(machine, {:improvement_result, call_id, result})

      assert machine.status == "reasoning"
      assert machine.act_triggered == false
      assert length(directives) == 1
    end
  end

  describe "answer_history accumulation" do
    test "accumulates answers across multiple improvement cycles" do
      machine = Machine.new(max_supervision_steps: 10, act_threshold: 0.99)

      # First cycle
      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})
      {machine, _} = Machine.update(machine, {:reasoning_result, "call_1", {:ok, %{text: "First"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:supervision_result, call_id, {:ok, %{text: "Score: 0.5"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:improvement_result, call_id, {:ok, %{text: "Second"}}})

      # Second cycle
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:reasoning_result, call_id, {:ok, %{text: "Reasoning 2"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:supervision_result, call_id, {:ok, %{text: "Score: 0.6"}}})
      call_id = machine.current_call_id
      {machine, _} = Machine.update(machine, {:improvement_result, call_id, {:ok, %{text: "Third"}}})

      assert machine.answer_history == ["Second", "Third"]
      assert machine.current_answer == "Third"
    end
  end

  describe "update/3 with :llm_partial message" do
    test "accumulates streaming text in reasoning state" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})

      {machine, directives} = Machine.update(machine, {:llm_partial, "call_1", "Hello ", :content})
      assert machine.streaming_text == "Hello "
      assert directives == []

      {machine, _} = Machine.update(machine, {:llm_partial, "call_1", "world", :content})
      assert machine.streaming_text == "Hello world"
    end

    test "ignores partial with wrong call_id" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})

      {machine, directives} = Machine.update(machine, {:llm_partial, "wrong_id", "data", :content})
      assert machine.streaming_text == ""
      assert directives == []
    end

    test "ignores non-content chunk types" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Question", "call_1"})

      {machine, _} = Machine.update(machine, {:llm_partial, "call_1", "thinking", :thinking})
      assert machine.streaming_text == ""
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trip preserves machine state" do
      machine = Machine.new(max_supervision_steps: 7, act_threshold: 0.85)
      {machine, _} = Machine.update(machine, {:start, "What is AI?", "call_1"})

      # Simulate some progress
      machine = %{machine |
        supervision_step: 2,
        current_answer: "AI is artificial intelligence",
        answer_history: ["First answer"],
        best_answer: "First answer",
        best_score: 0.7
      }

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.status == "reasoning"
      assert restored.question == "What is AI?"
      assert restored.supervision_step == 2
      assert restored.current_answer == "AI is artificial intelligence"
      assert restored.answer_history == ["First answer"]
      assert restored.best_answer == "First answer"
      assert restored.best_score == 0.7
      assert restored.max_supervision_steps == 7
      assert restored.act_threshold == 0.85
    end

    test "to_map converts status to atom" do
      machine = Machine.new()
      map = Machine.to_map(machine)

      assert map.status == :idle
    end

    test "from_map handles atom status" do
      map = %{status: :reasoning, question: "Test"}
      machine = Machine.from_map(map)

      assert machine.status == "reasoning"
    end

    test "from_map handles string status" do
      map = %{status: "supervising", question: "Test"}
      machine = Machine.from_map(map)

      assert machine.status == "supervising"
    end

    test "from_map provides defaults for missing fields" do
      machine = Machine.from_map(%{})

      assert machine.status == "idle"
      assert machine.max_supervision_steps == 5
      assert machine.act_threshold == 0.9
      assert machine.answer_history == []
    end
  end

  describe "generate_call_id/0" do
    test "generates unique IDs with trm prefix" do
      id1 = Machine.generate_call_id()
      id2 = Machine.generate_call_id()

      assert String.starts_with?(id1, "trm_")
      assert String.starts_with?(id2, "trm_")
      assert id1 != id2
    end
  end

  describe "latent state management" do
    test "initialize_latent_state/2 creates proper structure" do
      state = Machine.initialize_latent_state("Question", "Answer")

      assert state.question_context == "Question"
      assert state.answer_context == "Answer"
      assert state.reasoning_trace == []
      assert state.confidence_score == 0.0
      assert state.step_count == 0
    end

    test "update_latent_state/3 adds to reasoning trace" do
      state = Machine.initialize_latent_state("Q", nil)
      state = Machine.update_latent_state(state, :reasoning, "Some reasoning")

      assert length(state.reasoning_trace) == 1
      assert hd(state.reasoning_trace) =~ "[reasoning]"
      assert hd(state.reasoning_trace) =~ "Some reasoning"
    end

    test "extract_confidence/1 returns confidence score" do
      state = %{confidence_score: 0.75, reasoning_trace: []}
      assert Machine.extract_confidence(state) == 0.75
    end

    test "merge_reasoning_trace/2 limits trace size" do
      trace = Enum.map(1..15, &"Entry #{&1}")
      new_trace = Machine.merge_reasoning_trace(trace, "New entry")

      assert length(new_trace) == 10
      assert List.last(new_trace) == "New entry"
    end
  end

  describe "termination conditions" do
    test "should_terminate_max_steps?/1 returns true at max" do
      machine = %Machine{supervision_step: 5, max_supervision_steps: 5}
      assert Machine.should_terminate_max_steps?(machine)
    end

    test "should_terminate_max_steps?/1 returns false below max" do
      machine = %Machine{supervision_step: 3, max_supervision_steps: 5}
      refute Machine.should_terminate_max_steps?(machine)
    end

    test "check_act_condition/1 returns true above threshold" do
      machine = %Machine{
        act_threshold: 0.8,
        latent_state: %{confidence_score: 0.85, reasoning_trace: []}
      }
      assert Machine.check_act_condition(machine)
    end

    test "check_act_condition/1 returns false below threshold" do
      machine = %Machine{
        act_threshold: 0.9,
        latent_state: %{confidence_score: 0.7, reasoning_trace: []}
      }
      refute Machine.check_act_condition(machine)
    end
  end
end
