defmodule Jido.AI.Accuracy.ReflectionLoopTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, ReflectionLoop, ReflexionMemory}

  @moduletag :capture_log

  # Mock critiquer for testing
  defmodule MockCritiquer do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Critique

    defstruct []

    @impl true
    def critique(_critiquer, %Candidate{}, context) do
      # Severity decreases with iterations to simulate improvement
      iteration = Map.get(context, :iteration, 0)
      severity = 0.8 - (iteration * 0.3)

      {:ok,
       CritiqueResult.new!(%{
         severity: max(severity, 0.1),
         issues: ["Issue #{iteration + 1}"],
         suggestions: ["Fix #{iteration + 1}"],
         feedback: "Feedback for iteration #{iteration}"
       })}
    end
  end

  # Mock reviser for testing
  defmodule MockReviser do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Revision

    defstruct []

    @impl true
    def revise(_reviser, %Candidate{} = candidate, %CritiqueResult{}, context) do
      iteration = Map.get(context, :iteration, 0)

      {:ok,
       Candidate.new!(%{
         id: "#{candidate.id}-rev#{iteration}",
         content: String.trim(candidate.content || "") <> " [Improved #{iteration}]",
         score: 0.5 + (iteration * 0.2),
         metadata: Map.put(candidate.metadata || %{}, :iteration, iteration)
       })}
    end
  end

  # Mock generator
  defmodule MockGenerator do
    @moduledoc false

    def generate_candidates(_generator, _prompt, _opts) do
      {:ok,
       [
         Candidate.new!(%{
           id: "generated-1",
           content: "Generated response",
           score: 0.5
         })
       ]}
    end
  end

  describe "new/1" do
    test "creates loop with defaults" do
      assert {:ok, loop} =
               ReflectionLoop.new(%{
                 critiquer: MockCritiquer,
                 reviser: MockReviser
               })

      assert loop.max_iterations == 3
      assert loop.convergence_threshold == 0.1
      assert loop.critiquer == MockCritiquer
      assert loop.reviser == MockReviser
    end

    test "creates loop with custom options" do
      assert {:ok, loop} =
               ReflectionLoop.new(%{
                 critiquer: MockCritiquer,
                 reviser: MockReviser,
                 max_iterations: 5,
                 convergence_threshold: 0.2
               })

      assert loop.max_iterations == 5
      assert loop.convergence_threshold == 0.2
    end

    test "creates loop with memory" do
      memory = ReflexionMemory.new!(%{storage: :ets})

      assert {:ok, loop} =
               ReflectionLoop.new(%{
                 critiquer: MockCritiquer,
                 reviser: MockReviser,
                 memory: memory
               })

      assert loop.memory == memory

      ReflexionMemory.stop(memory)
    end

    test "returns error without critiquer" do
      assert {:error, :critiquer_required} = ReflectionLoop.new(%{reviser: MockReviser})
    end

    test "returns error without reviser" do
      assert {:error, :reviser_required} = ReflectionLoop.new(%{critiquer: MockCritiquer})
    end

    test "returns error for invalid max_iterations" do
      assert {:error, :invalid_max_iterations} =
               ReflectionLoop.new(%{
                 critiquer: MockCritiquer,
                 reviser: MockReviser,
                 max_iterations: 0
               })
    end

    test "returns error for invalid convergence_threshold" do
      assert {:error, :invalid_convergence_threshold} =
               ReflectionLoop.new(%{
                 critiquer: MockCritiquer,
                 reviser: MockReviser,
                 convergence_threshold: 1.5
               })
    end
  end

  describe "new!/1" do
    test "returns loop when valid" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser
        })

      assert %ReflectionLoop{} = loop
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid ReflectionLoop/, fn ->
        ReflectionLoop.new!(%{critiquer: MockCritiquer})
      end
    end
  end

  describe "run/3" do
    test "executes multiple iterations" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          max_iterations: 3
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      assert {:ok, result} = ReflectionLoop.run(loop, "Test prompt", %{initial_candidate: initial})

      assert result.converged == true
      assert result.total_iterations > 0
      assert %Candidate{} = result.best_candidate
      assert is_list(result.iterations)
      assert length(result.iterations) <= 3
    end

    test "respects max_iterations limit" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      assert {:ok, result} = ReflectionLoop.run(loop, "Test prompt", %{initial_candidate: initial})

      assert result.total_iterations <= 2
    end

    test "requires initial candidate when no generator" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser
        })

      assert {:error, :no_initial_candidate} = ReflectionLoop.run(loop, "Test prompt", %{})
    end

    test "generates initial candidate when generator provided" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          generator: MockGenerator
        })

      assert {:ok, result} = ReflectionLoop.run(loop, "Test prompt", %{})

      assert %Candidate{} = result.best_candidate
    end

    test "tracks iteration history" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          max_iterations: 3
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      assert {:ok, result} = ReflectionLoop.run(loop, "Test prompt", %{initial_candidate: initial})

      # Check that iterations are tracked
      assert length(result.iterations) > 0

      # Check first iteration structure
      first_iter = List.first(result.iterations)

      assert is_integer(first_iter.iteration)
      assert %Candidate{} = first_iter.candidate
      assert %CritiqueResult{} = first_iter.critique
    end

    test "selects best candidate across iterations" do
      # Mock that produces different scores
      defmodule ScoringReviser do
        @behaviour Jido.AI.Accuracy.Revision

        defstruct []

        @impl true
        def revise(_reviser, %Candidate{} = candidate, _critique, context) do
          iteration = Map.get(context, :iteration, 0)

          {:ok,
           Candidate.new!(%{
             id: "#{candidate.id}-rev#{iteration}",
             content: "Revised #{iteration}",
             score: 0.3 + (iteration * 0.25)
           })}
        end
      end

      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: ScoringReviser,
          max_iterations: 3
        })

      initial = Candidate.new!(%{id: "1", content: "Initial", score: 0.2})

      assert {:ok, result} = ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      # Best candidate should have highest score
      assert result.best_candidate.score >= initial.score
    end
  end

  describe "run_iteration/5" do
    test "executes single critique-revise cycle" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser
        })

      candidate = Candidate.new!(%{id: "1", content: "Test"})

      assert {:ok, step} = ReflectionLoop.run_iteration(loop, "Prompt", candidate, 0, %{})

      assert %Candidate{} = step.candidate
      assert %CritiqueResult{} = step.critique
      assert is_boolean(step.converged)
    end

    test "includes iteration number in context" do
      defmodule ContextCheckingReviser do
        @behaviour Jido.AI.Accuracy.Revision

        defstruct []

        @impl true
        def revise(_reviser, _candidate, _critique, context) do
          iter = Map.get(context, :iteration)
          {:ok, Candidate.new!(%{id: "ctx-#{iter}", content: "Context received"})}
        end
      end

      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: ContextCheckingReviser
        })

      candidate = Candidate.new!(%{id: "1", content: "Test"})

      assert {:ok, step} = ReflectionLoop.run_iteration(loop, "Prompt", candidate, 2, %{})

      assert step.candidate.id == "ctx-2"
    end
  end

  describe "check_convergence/4" do
    test "returns true when critique severity is low" do
      loop = ReflectionLoop.new!(%{critiquer: MockCritiquer, reviser: MockReviser})

      candidate1 = Candidate.new!(%{id: "1", content: "Original"})

      candidate2 = Candidate.new!(%{id: "2", content: "Revised"})

      critique = CritiqueResult.new!(%{severity: 0.2})

      assert ReflectionLoop.check_convergence(loop, critique, candidate1, candidate2) == true
    end

    test "returns true when content change is minimal" do
      loop = ReflectionLoop.new!(%{critiquer: MockCritiquer, reviser: MockReviser})

      candidate1 = Candidate.new!(%{id: "1", content: "Same content here"})

      candidate2 = Candidate.new!(%{id: "2", content: "Same content here "})

      critique = CritiqueResult.new!(%{severity: 0.8})

      assert ReflectionLoop.check_convergence(loop, critique, candidate1, candidate2) == true
    end

    test "returns true when score plateau is reached" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          convergence_threshold: 0.1
        })

      candidate1 = Candidate.new!(%{id: "1", content: "One", score: 0.85})

      candidate2 = Candidate.new!(%{id: "2", content: "Two", score: 0.88})

      critique = CritiqueResult.new!(%{severity: 0.8})

      assert ReflectionLoop.check_convergence(loop, critique, candidate1, candidate2) == true
    end

    test "returns false when no convergence criteria met" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          convergence_threshold: 0.1
        })

      candidate1 = Candidate.new!(%{id: "1", content: "Original content"})

      candidate2 = Candidate.new!(%{id: "2", content: "Completely different revised content"})

      critique = CritiqueResult.new!(%{severity: 0.7})

      assert ReflectionLoop.check_convergence(loop, critique, candidate1, candidate2) == false
    end
  end

  describe "improvement_score/3" do
    test "calculates improvement from critique severity" do
      critique = CritiqueResult.new!(%{severity: 0.6})

      score =
        ReflectionLoop.improvement_score(
          Candidate.new!(%{id: "1"}),
          Candidate.new!(%{id: "2"}),
          critique
        )

      assert score == 0.4
    end

    test "calculates improvement from candidate scores" do
      score =
        ReflectionLoop.improvement_score(
          Candidate.new!(%{id: "1", score: 0.5}),
          Candidate.new!(%{id: "2", score: 0.8}),
          nil
        )

      assert_in_delta score, 0.3, 0.001
    end

    test "returns 0 when no scores available" do
      score =
        ReflectionLoop.improvement_score(
          Candidate.new!(%{id: "1"}),
          Candidate.new!(%{id: "2"}),
          nil
        )

      assert score == 0.0
    end
  end

  describe "integration with ReflexionMemory" do
    test "retrieves past mistakes for context" do
      memory = ReflexionMemory.new!(%{storage: :ets})

      # Store a past mistake
      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "What is 15 * 23?",
          mistake: "Calculation error",
          correction: "15 * 23 = 345"
        })

      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          memory: memory
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      # Similar prompt should benefit from memory
      assert {:ok, _result} =
               ReflectionLoop.run(loop, "Calculate 15 * 23", %{initial_candidate: initial})

      ReflexionMemory.stop(memory)
    end

    test "stores high-severity critiques in memory" do
      defmodule HighSeverityCritiquer do
        @behaviour Jido.AI.Accuracy.Critique

        defstruct []

        @impl true
        def critique(_critiquer, _candidate, _context) do
          {:ok,
           CritiqueResult.new!(%{
             severity: 0.8,
             issues: ["Calculation error"],
             suggestions: ["Check math"]
           })}
        end
      end

      memory = ReflexionMemory.new!(%{storage: :ets})

      loop =
        ReflectionLoop.new!(%{
          critiquer: HighSeverityCritiquer,
          reviser: MockReviser,
          memory: memory
        })

      initial = Candidate.new!(%{id: "1", content: "Wrong answer"})

      {:ok, _result} = ReflectionLoop.run(loop, "What is 2+2?", %{initial_candidate: initial})

      # Check that critique was stored
      assert ReflexionMemory.count(memory) > 0

      ReflexionMemory.stop(memory)
    end
  end

  describe "result structure" do
    test "returns complete result structure" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: MockCritiquer,
          reviser: MockReviser,
          max_iterations: 1
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      {:ok, result} = ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      assert Map.has_key?(result, :best_candidate)
      assert Map.has_key?(result, :iterations)
      assert Map.has_key?(result, :converged)
      assert Map.has_key?(result, :reason)
      assert Map.has_key?(result, :total_iterations)
    end

    test "provides convergence reason" do
      defmodule ConvergingCritiquer do
        @behaviour Jido.AI.Accuracy.Critique

        defstruct []

        @impl true
        def critique(_critiquer, _candidate, _context) do
          {:ok, CritiqueResult.new!(%{severity: 0.1})}
        end
      end

      loop =
        ReflectionLoop.new!(%{
          critiquer: ConvergingCritiquer,
          reviser: MockReviser
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      {:ok, result} = ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      assert result.converged == true
      assert result.reason == :converged
    end

    test "provides max_iterations reason when limit reached" do
      defmodule NonConvergingCritiquer do
        @behaviour Jido.AI.Accuracy.Critique

        defstruct []

        @impl true
        def critique(_critiquer, _candidate, _context) do
          {:ok, CritiqueResult.new!(%{severity: 0.8})}
        end
      end

      loop =
        ReflectionLoop.new!(%{
          critiquer: NonConvergingCritiquer,
          reviser: MockReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "1", content: "Initial"})

      {:ok, result} = ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      assert result.reason == :max_iterations
    end
  end
end
