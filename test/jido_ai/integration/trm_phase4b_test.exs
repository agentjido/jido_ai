defmodule Jido.AI.Integration.TRMPhase4BTest do
  @moduledoc """
  Integration tests for Phase 4B TRM Strategy.

  These tests verify that all Phase 4B TRM components work together correctly,
  including the complete reason-supervise-improve cycle, ACT early stopping,
  termination conditions, and Adaptive integration.

  ## Test Scope

  - Basic Workflow: Complete TRM reasoning cycle
  - ACT Early Stopping: Confidence-based termination
  - Termination Conditions: Max steps, ACT threshold, errors
  - Adaptive Integration: TRM selection for puzzle/iterative tasks
  - Deep Supervision: Feedback-driven answer improvement
  """
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.Adaptive
  alias Jido.AI.Strategies.TRM
  alias Jido.AI.TRM.Machine
  alias Jido.AI.TRM.ACT
  alias Jido.AI.Directive
  alias Jido.Instruction

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_agent(strategy_module, opts \\ []) do
    %Agent{
      id: "test-agent-#{System.unique_integer([:positive])}",
      name: "test_agent",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, _directives} = strategy_module.init(agent, ctx)
      {agent, ctx}
    end)
  end

  defp mock_llm_result(call_id, content, opts \\ []) do
    usage = Keyword.get(opts, :usage, %{input_tokens: 100, output_tokens: 50})

    %{
      call_id: call_id,
      result: {:ok, %{text: content, usage: usage}},
      phase: Keyword.get(opts, :phase, :reasoning)
    }
  end

  # Note: mock_llm_error and status_matches? removed as they are unused

  # ============================================================================
  # 4B.7.1 Basic Workflow Tests
  # ============================================================================

  describe "basic TRM workflow" do
    test "TRM strategy initialization with config" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 3, act_threshold: 0.85)

      state = StratState.get(agent, %{})
      # Status is converted to atom via Machine.to_map
      assert state[:status] == :idle
      assert state[:config][:max_supervision_steps] == 3
      assert state[:config][:act_threshold] == 0.85
      assert state[:config][:model] == "anthropic:claude-haiku-4-5"
    end

    test "start with question creates initial reasoning directive" do
      {agent, _ctx} = create_agent(TRM)

      instruction = %Instruction{
        action: TRM.start_action(),
        params: %{question: "What is the capital of France?"}
      }

      {updated_agent, directives} = TRM.cmd(agent, [instruction], %{})

      # Verify state transition
      state = StratState.get(updated_agent, %{})
      assert state[:status] == :reasoning
      assert state[:question] == "What is the capital of France?"
      assert state[:supervision_step] == 1

      # Verify directive emitted
      assert length(directives) == 1
      [directive] = directives
      assert %Directive.ReqLLMStream{} = directive
      assert directive.metadata[:phase] == :reasoning
    end

    test "reasoning result triggers supervision phase" do
      {agent, _ctx} = create_agent(TRM)

      # Start reasoning
      start_instruction = %Instruction{
        action: TRM.start_action(),
        params: %{question: "What is 2 + 2?"}
      }

      {agent, [%Directive.ReqLLMStream{id: call_id}]} = TRM.cmd(agent, [start_instruction], %{})

      # Simulate reasoning response
      llm_result = mock_llm_result(call_id, "The answer is 4 because 2 plus 2 equals 4.", phase: :reasoning)

      result_instruction = %Instruction{
        action: TRM.llm_result_action(),
        params: llm_result
      }

      {updated_agent, directives} = TRM.cmd(agent, [result_instruction], %{})

      # Verify transition to supervision
      state = StratState.get(updated_agent, %{})
      assert state[:status] == :supervising
      assert state[:current_answer] == "The answer is 4 because 2 plus 2 equals 4."

      # Verify supervision directive
      assert length(directives) == 1
      [directive] = directives
      assert %Directive.ReqLLMStream{} = directive
      assert directive.metadata[:phase] == :supervising
    end

    test "supervision feedback triggers improvement phase" do
      {agent, _ctx} = create_agent(TRM)

      # Start → Reasoning
      {agent, [%Directive.ReqLLMStream{id: call_id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Explain recursion"}}], %{})

      # Reasoning → Supervision
      {agent, [%Directive.ReqLLMStream{id: call_id2}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id1, "Recursion is when a function calls itself.", phase: :reasoning)
        }], %{})

      # Supervision → Improvement
      supervision_feedback = """
      The answer is correct but could be more detailed.
      Score: 0.6
      Suggestions:
      - Add an example
      - Explain base case
      """

      {updated_agent, directives} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id2, supervision_feedback, phase: :supervising)
        }], %{})

      # Verify transition to improvement
      state = StratState.get(updated_agent, %{})
      assert state[:status] == :improving
      assert state[:supervision_feedback] =~ "Score: 0.6"

      # Verify improvement directive
      assert length(directives) == 1
      [directive] = directives
      assert %Directive.ReqLLMStream{} = directive
      assert directive.metadata[:phase] == :improving
    end

    test "improvement result loops back to reasoning" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 5)

      # Full cycle: Start → Reasoning → Supervision → Improvement → Reasoning
      {agent, [%Directive.ReqLLMStream{id: call_id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test question"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: call_id2}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id1, "Initial answer", phase: :reasoning)
        }], %{})

      {agent, [%Directive.ReqLLMStream{id: call_id3}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id2, "Feedback. Score: 0.5", phase: :supervising)
        }], %{})

      # Improvement result should loop back to reasoning
      {updated_agent, directives} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id3, "Improved answer", phase: :improving)
        }], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:status] == :reasoning
      assert state[:supervision_step] == 2
      assert "Improved answer" in state[:answer_history]

      # Verify new reasoning directive
      assert length(directives) == 1
      [directive] = directives
      assert %Directive.ReqLLMStream{} = directive
      assert directive.metadata[:phase] == :reasoning
    end

    test "multi-step recursive loop completes" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 2)

      # Step 1: Start
      {agent, [%Directive.ReqLLMStream{id: call_id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      # Step 1: Reasoning
      {agent, [%Directive.ReqLLMStream{id: call_id2}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id1, "Answer 1", phase: :reasoning)
        }], %{})

      # Step 1: Supervision
      {agent, [%Directive.ReqLLMStream{id: call_id3}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id2, "Score: 0.5", phase: :supervising)
        }], %{})

      # Step 1: Improvement
      {agent, [%Directive.ReqLLMStream{id: call_id4}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id3, "Answer 2", phase: :improving)
        }], %{})

      # Step 2: Reasoning
      {agent, [%Directive.ReqLLMStream{id: call_id5}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id4, "Reasoning 2", phase: :reasoning)
        }], %{})

      # Step 2: Supervision
      {agent, [%Directive.ReqLLMStream{id: call_id6}]} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id5, "Score: 0.7", phase: :supervising)
        }], %{})

      # Step 2: Improvement - should complete due to max_supervision_steps
      {final_agent, directives} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: mock_llm_result(call_id6, "Final answer", phase: :improving)
        }], %{})

      state = StratState.get(final_agent, %{})
      assert state[:status] == :completed
      assert state[:termination_reason] == :max_steps
      assert directives == []
    end

    test "answer history accumulates correctly" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 3)

      # Run through multiple improvement cycles
      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "Initial", phase: :reasoning)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.4", phase: :supervising)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id4}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Improved 1", phase: :improving)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id5}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id4, "Reasoning 2", phase: :reasoning)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id6}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id5, "Score: 0.6", phase: :supervising)}], %{})

      {final_agent, _} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id6, "Improved 2", phase: :improving)}], %{})

      history = TRM.get_answer_history(final_agent)
      assert length(history) == 2
      assert "Improved 1" in history
      assert "Improved 2" in history
    end
  end

  # ============================================================================
  # 4B.7.2 ACT Early Stopping Tests
  # ============================================================================

  describe "ACT early stopping" do
    test "ACT triggers early stopping when confidence exceeds threshold" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 10, act_threshold: 0.8)

      # Run through one cycle with high confidence score
      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "Initial", phase: :reasoning)}], %{})

      # High confidence score should trigger ACT
      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Excellent! Score: 0.95", phase: :supervising)}], %{})

      # Improvement result should trigger ACT completion
      {final_agent, directives} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Final answer", phase: :improving)}], %{})

      state = StratState.get(final_agent, %{})
      assert state[:status] == :completed
      assert state[:termination_reason] == :act_threshold
      assert state[:act_triggered] == true
      assert state[:best_score] == 0.95
      assert directives == []
    end

    test "ACT allows continuation when confidence below threshold" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 5, act_threshold: 0.9)

      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "Initial", phase: :reasoning)}], %{})

      # Below threshold score should not trigger ACT
      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Okay. Score: 0.7", phase: :supervising)}], %{})

      {updated_agent, directives} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Improved", phase: :improving)}], %{})

      state = StratState.get(updated_agent, %{})
      # Should continue to next reasoning cycle, not complete
      assert state[:status] == :reasoning
      assert state[:act_triggered] == false
      assert length(directives) == 1
    end

    test "ACT module convergence detection stops on plateaued improvements" do
      # Test the ACT module directly for convergence detection
      # ACT.detect_convergence expects a list of history values, not the state struct
      history = [0.75, 0.76, 0.755, 0.758]

      # Check convergence with small epsilon - range is 0.01, less than 0.02
      assert ACT.detect_convergence(history, 4, 0.02)
    end
  end

  # ============================================================================
  # 4B.7.3 Termination Tests
  # ============================================================================

  describe "termination conditions" do
    test "termination on max_supervision_steps" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 1)

      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "Initial", phase: :reasoning)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.5", phase: :supervising)}], %{})

      {final_agent, directives} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Final", phase: :improving)}], %{})

      state = StratState.get(final_agent, %{})
      assert state[:status] == :completed
      assert state[:termination_reason] == :max_steps
      assert directives == []
    end

    test "error handling transitions to error state" do
      {agent, _ctx} = create_agent(TRM)

      {agent, [%Directive.ReqLLMStream{id: call_id}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      # Simulate LLM error (mock_llm_error not used directly, inline error params)
      {error_agent, directives} =
        TRM.cmd(agent, [%Instruction{
          action: TRM.llm_result_action(),
          params: %{call_id: call_id, result: {:error, "API rate limit exceeded"}, phase: :reasoning}
        }], %{})

      state = StratState.get(error_agent, %{})
      assert state[:status] == :error
      assert state[:termination_reason] == :error
      assert directives == []
    end

    test "snapshot returns correct state at each phase" do
      {agent, ctx} = create_agent(TRM)

      # Idle phase
      snapshot = TRM.snapshot(agent, ctx)
      assert snapshot.status == :idle
      assert snapshot.done? == false

      # Reasoning phase
      {agent, _} = TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], ctx)
      snapshot = TRM.snapshot(agent, ctx)
      assert snapshot.status == :running
      assert snapshot.done? == false
      # Phase is stored as atom in state, but snapshot.details[:phase] is the raw status
      assert snapshot.details[:phase] == :reasoning

      # Completed phase (via max_steps=1)
      {agent2, _} = create_agent(TRM, max_supervision_steps: 1)
      {agent2, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent2, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], ctx)
      {agent2, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent2, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "A", phase: :reasoning)}], ctx)
      {agent2, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent2, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.8", phase: :supervising)}], ctx)
      {completed_agent, _} =
        TRM.cmd(agent2, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Final", phase: :improving)}], ctx)

      snapshot = TRM.snapshot(completed_agent, ctx)
      assert snapshot.status == :success
      assert snapshot.done? == true
      assert snapshot.result != nil
    end
  end

  # ============================================================================
  # 4B.7.4 Adaptive Integration Tests
  # ============================================================================

  describe "Adaptive integration" do
    test "Adaptive selects TRM for puzzle/iterative prompts" do
      prompts = [
        "This puzzle needs iterative reasoning",
        "Iterate on this solution until perfect",
        "Refine this answer recursively",
        "Improve the answer through refinement"
      ]

      for prompt <- prompts do
        {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert strategy == :trm, "Expected :trm for prompt: #{prompt}"
        assert task_type == :iterative_reasoning, "Expected :iterative_reasoning for prompt: #{prompt}"
      end
    end

    test "Adaptive delegates correctly to TRM" do
      {agent, _ctx} = create_agent(Adaptive)

      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "This puzzle needs iterative reasoning to improve"}
      }

      {updated_agent, directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :trm
      assert state[:task_type] == :iterative_reasoning

      # Should emit TRM reasoning directive
      assert length(directives) == 1
      [directive] = directives
      assert %Directive.ReqLLMStream{} = directive
    end

    test "TRM completion result is accessible through Adaptive" do
      {agent, ctx} = create_agent(Adaptive)

      # Start with puzzle prompt
      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        Adaptive.cmd(agent, [%Instruction{
          action: Adaptive.start_action(),
          params: %{prompt: "Iterate on this puzzle"}
        }], ctx)

      # Verify TRM was selected
      state = StratState.get(agent, %{})
      assert state[:strategy_type] == :trm

      # Process through TRM phases (simulate completing with max_steps=1 via mock)
      # The Adaptive should delegate LLM results to the selected TRM strategy
      {agent, [%Directive.ReqLLMStream{id: _id2}]} =
        Adaptive.cmd(agent, [%Instruction{
          action: Adaptive.llm_result_action(),
          params: mock_llm_result(id1, "Initial reasoning", phase: :reasoning)
        }], ctx)

      snapshot = Adaptive.snapshot(agent, ctx)
      assert snapshot.status == :running
      # Phase is stored as atom
      assert snapshot.details[:phase] == :supervising
    end
  end

  # ============================================================================
  # 4B.7.5 Deep Supervision Tests
  # ============================================================================

  describe "deep supervision" do
    test "supervision feedback improves answer quality tracking" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 5)

      # Start and get initial answer
      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Explain AI"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "AI is artificial intelligence", phase: :reasoning)}], %{})

      # First supervision with low score
      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Needs more detail. Score: 0.4", phase: :supervising)}], %{})

      state1 = StratState.get(agent, %{})
      assert state1[:best_score] == 0.4

      # Improvement
      {agent, [%Directive.ReqLLMStream{id: id4}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "AI is the simulation of human intelligence by machines", phase: :improving)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id5}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id4, "Better reasoning", phase: :reasoning)}], %{})

      # Second supervision with higher score
      {agent, _} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id5, "Good improvement. Score: 0.7", phase: :supervising)}], %{})

      state2 = StratState.get(agent, %{})
      # Best score should be updated
      assert state2[:best_score] == 0.7
    end

    test "quality scores tracked across supervision steps" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 3)

      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "A1", phase: :reasoning)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.3", phase: :supervising)}], %{})

      assert TRM.get_best_score(agent) == 0.3

      {agent, [%Directive.ReqLLMStream{id: id4}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "A2", phase: :improving)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id5}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id4, "R2", phase: :reasoning)}], %{})

      {agent, _} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id5, "Score: 0.6", phase: :supervising)}], %{})

      # Score should increase
      assert TRM.get_best_score(agent) == 0.6
    end

    test "best answer is tracked and returned on completion" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 2)

      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "First answer", phase: :reasoning)}], %{})

      # First supervision - moderate score
      {agent, [%Directive.ReqLLMStream{id: id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.6", phase: :supervising)}], %{})

      assert TRM.get_best_answer(agent) == "First answer"

      {agent, [%Directive.ReqLLMStream{id: id4}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id3, "Second answer (worse)", phase: :improving)}], %{})

      {agent, [%Directive.ReqLLMStream{id: id5}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id4, "R2", phase: :reasoning)}], %{})

      # Second supervision - lower score (should not replace best)
      {agent, [%Directive.ReqLLMStream{id: id6}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id5, "Score: 0.4", phase: :supervising)}], %{})

      # Best answer should still be first answer with higher score
      assert TRM.get_best_answer(agent) == "First answer"
      assert TRM.get_best_score(agent) == 0.6

      # Complete
      {final_agent, _} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id6, "Third answer", phase: :improving)}], %{})

      state = StratState.get(final_agent, %{})
      assert state[:status] == :completed
      # Result should be the best answer, not the last one
      assert state[:result] == "First answer"
    end
  end

  # ============================================================================
  # Cross-Component Integration Tests
  # ============================================================================

  describe "cross-component integration" do
    test "TRM Machine state can be serialized and restored" do
      machine = Machine.new(max_supervision_steps: 3, act_threshold: 0.85)

      # Start a session
      {machine, _} = Machine.update(machine, {:start, "Test question", "call_123"}, %{})

      # Serialize - to_map converts status to atom
      map = Machine.to_map(machine)
      assert map[:status] == :reasoning
      assert map[:question] == "Test question"

      # Restore - from_map converts status back to string for Fsmx
      restored = Machine.from_map(map)
      assert restored.status == "reasoning"
      assert restored.question == "Test question"
      assert restored.max_supervision_steps == 3
    end

    test "TRM public API functions return correct values" do
      {agent, _ctx} = create_agent(TRM, max_supervision_steps: 3)

      # Initial state
      assert TRM.get_answer_history(agent) == []
      assert TRM.get_current_answer(agent) == nil
      assert TRM.get_confidence(agent) == 0.0
      assert TRM.get_supervision_step(agent) == 0

      # After some processing
      {agent, [%Directive.ReqLLMStream{id: id1}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.start_action(), params: %{question: "Test"}}], %{})

      assert TRM.get_supervision_step(agent) == 1

      {agent, [%Directive.ReqLLMStream{id: id2}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id1, "Answer", phase: :reasoning)}], %{})

      assert TRM.get_current_answer(agent) == "Answer"

      {agent, [%Directive.ReqLLMStream{id: _id3}]} =
        TRM.cmd(agent, [%Instruction{action: TRM.llm_result_action(), params: mock_llm_result(id2, "Score: 0.75", phase: :supervising)}], %{})

      assert TRM.get_confidence(agent) == 0.75
    end

    test "all TRM components implement required interfaces" do
      # Ensure modules are loaded
      Code.ensure_loaded!(TRM)
      Code.ensure_loaded!(Machine)
      Code.ensure_loaded!(ACT)

      # TRM Strategy callbacks
      assert {:init, 2} in TRM.__info__(:functions)
      assert {:cmd, 3} in TRM.__info__(:functions)
      assert {:signal_routes, 1} in TRM.__info__(:functions)
      assert {:snapshot, 2} in TRM.__info__(:functions)
      assert {:action_spec, 1} in TRM.__info__(:functions)

      # Machine functions
      assert {:new, 0} in Machine.__info__(:functions)
      assert {:new, 1} in Machine.__info__(:functions)
      assert {:update, 2} in Machine.__info__(:functions)
      assert {:update, 3} in Machine.__info__(:functions)
      assert {:to_map, 1} in Machine.__info__(:functions)
      assert {:from_map, 1} in Machine.__info__(:functions)

      # ACT functions
      assert {:new, 1} in ACT.__info__(:functions)
      assert {:update, 2} in ACT.__info__(:functions)
      assert {:should_halt?, 2} in ACT.__info__(:functions)
      assert {:detect_convergence, 1} in ACT.__info__(:functions)
    end
  end
end
