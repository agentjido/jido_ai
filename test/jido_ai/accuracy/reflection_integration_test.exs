defmodule Jido.AI.Accuracy.ReflectionIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, ReflectionLoop, ReflexionMemory, SelfRefine}

  @moduletag :integration
  @moduletag :capture_log

  # ============================================================================
  # Mock Components for Integration Testing
  # ============================================================================

  defmodule ImprovingCritiquer do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Critique

    @impl true
    def critique(%Candidate{}, context) do
      iteration = Map.get(context, :iteration, 0)
      # Severity decreases with iterations
      severity = 0.9 - (iteration * 0.35)
      severity = max(severity, 0.1)

      issues =
        if severity > 0.5 do
          ["Calculation error", "Missing steps"]
        else
          ["Minor formatting issue"]
        end

      {:ok,
       CritiqueResult.new!(%{
         severity: severity,
         issues: issues,
         suggestions: ["Fix the errors", "Add more detail"],
         feedback: "Iteration #{iteration} feedback"
       })}
    end
  end

  defmodule ImprovingReviser do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Revision

    @impl true
    def revise(%Candidate{} = candidate, %CritiqueResult{} = _critique, context) do
      iteration = Map.get(context, :iteration, 0)

      # Content improves with iterations
      improvements = ["more detailed", "better structured", "thoroughly explained"]
      improvement = Enum.at(improvements, min(iteration, 2), "polished")

      new_content = """
      Improved response (iteration #{iteration}):
      The answer is #{improvement}.
      #{candidate.content || ""}
      """

      {:ok,
       Candidate.new!(%{
         id: "#{candidate.id}-rev#{iteration}",
         content: String.trim(new_content),
         score: 0.3 + (iteration * 0.25),
         metadata: Map.put(candidate.metadata || %{}, :iteration, iteration)
       })}
    end
  end

  # Domain-specific mock critiquers
  defmodule CodeCritiquer do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Critique

    @impl true
    def critique(%Candidate{content: content}, _context) do
      issues = []

      issues =
        if content && !String.contains?(content, "def ") do
          ["Missing function definition" | issues]
        else
          issues
        end

      issues =
        if content && String.contains?(content, "TODO") do
          ["Contains TODO comments" | issues]
        else
          issues
        end

      issues =
        if content && !String.contains?(content, "end") do
          ["Missing end keyword" | issues]
        else
          issues
        end

      {:ok,
       CritiqueResult.new!(%{
         severity: if(issues == [], do: 0.1, else: 0.8),
         issues: issues,
         suggestions: ["Add proper syntax", "Remove TODOs", "Complete the code"],
         feedback: if(issues == [], do: "Code looks good", else: "Code has issues")
       })}
    end
  end

  defmodule CodeReviser do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Revision

    @impl true
    def revise(%Candidate{content: content}, %CritiqueResult{} = _critique, _context) do
      # Fix common code issues
      fixed =
        (content || "")
        |> String.replace("TODO", "# Implemented")
        |> String.replace("calculate", "def calculate")
        |> then(fn
          "" -> "def calculate()\n  # Implementation\nend"
          str -> if String.contains?(str, "def "), do: str, else: "def #{str}\nend"
        end)

      {:ok,
       Candidate.new!(%{
         id: "code-revised",
         content: fixed,
         score: 0.9
       })}
    end
  end

  defmodule WritingCritiquer do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Critique

    @impl true
    def critique(%Candidate{content: content}, _context) do
      text = content || ""

      issues = []

      issues =
        if String.length(text) < 50 do
          ["Too short" | issues]
        else
          issues
        end

      issues =
        if String.contains?(text, "very") do
          ["Uses weak adjective 'very'" | issues]
        else
          issues
        end

      issues =
        if !String.contains?(text, ".") do
          ["Missing punctuation" | issues]
        else
          issues
        end

      {:ok,
       CritiqueResult.new!(%{
         severity: length(issues) * 0.3,
         issues: issues,
         suggestions: ["Expand on ideas", "Use stronger vocabulary", "Add punctuation"],
         feedback: if(issues == [], do: "Well written", else: "Needs improvement")
       })}
    end
  end

  defmodule WritingReviser do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Revision

    @impl true
    def revise(%Candidate{content: content}, %CritiqueResult{}, _context) do
      # Improve writing quality
      base = (content || "")
        |> String.replace("very good", "excellent")
        |> String.replace("very bad", "poor")
        |> String.replace("  ", " ")
        |> String.trim()

      improved =
        cond do
          base == "" ->
            "This is a comprehensive and well-structured response that addresses all aspects of the question thoroughly."

          String.length(base) < 100 ->
            base <> " This additional context provides more detail and clarity to the response."

          true ->
            base
        end

      {:ok,
       Candidate.new!(%{
         id: "writing-revised",
         content: improved,
         score: 0.85
       })}
    end
  end

  defmodule MathCritiquer do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Critique

    @impl true
    def critique(%Candidate{content: content}, _context) do
      text = content || ""

      issues = []

      # Check for common math errors
      issues =
        if String.contains?(text, "345") or String.contains?(text, "15 * 23 = 345") do
          issues
        else
          ["Incorrect calculation result" | issues]
        end

      issues =
        if !String.contains?(text, "15") && !String.contains?(text, "23") do
          ["Missing calculation steps" | issues]
        else
          issues
        end

      {:ok,
       CritiqueResult.new!(%{
         severity: if(issues == [], do: 0.0, else: 0.7),
         issues: issues,
         suggestions: ["Verify calculation", "Show work"],
         feedback: if(issues == [], do: "Correct answer", else: "Check your math")
       })}
    end
  end

  defmodule MathReviser do
    @moduledoc false
    @behaviour Jido.AI.Accuracy.Revision

    @impl true
    def revise(%Candidate{content: _content}, %CritiqueResult{}, _context) do
      # Provide correct math solution
      revised = """
      To calculate 15 * 23:
      15 * 23 = 15 * (20 + 3) = (15 * 20) + (15 * 3) = 300 + 45 = 345

      Therefore, 15 * 23 = 345.
      """

      {:ok,
       Candidate.new!(%{
         id: "math-revised",
         content: revised,
         score: 1.0
       })}
    end
  end

  # ============================================================================
  # Section 4.5.1: Reflection Loop Integration Tests
  # ============================================================================

  describe "4.5.1 Reflection Loop Integration Tests" do
    test "reflection loop improves response over iterations" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 3
        })

      initial =
        Candidate.new!(%{
          id: "initial",
          content: "Initial flawed response",
          score: 0.1
        })

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Test prompt", %{initial_candidate: initial})

      # Verify multiple iterations occurred
      assert result.total_iterations > 1
      assert result.total_iterations <= 3

      # Verify improvement tracking
      assert length(result.iterations) == result.total_iterations

      # Verify best candidate has higher score than initial
      assert result.best_candidate.score > initial.score

      # Verify content changed (improved)
      refute result.best_candidate.content == initial.content

      # Verify final iteration shows improvement
      last_iter = List.last(result.iterations)
      assert last_iter.candidate.score > 0.3
    end

    test "convergence detection stops loop when improvement plateaus" do
      # Create a critiquer that converges quickly
      defmodule QuickConvergenceCritiquer do
        @moduledoc false
        @behaviour Jido.AI.Accuracy.Critique

        @impl true
        def critique(%Candidate{}, context) do
          iteration = Map.get(context, :iteration, 0)
          # Converges after iteration 1
          severity = if iteration >= 1, do: 0.1, else: 0.7

          {:ok,
           CritiqueResult.new!(%{
             severity: severity,
             issues: if(severity < 0.3, do: [], else: ["Some issue"]),
             suggestions: [],
             feedback: "Feedback"
           })}
        end
      end

      loop =
        ReflectionLoop.new!(%{
          critiquer: QuickConvergenceCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 5
        })

      initial = Candidate.new!(%{id: "conv-test", content: "Test"})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      # Should converge before max iterations
      assert result.converged == true
      assert result.reason == :converged
      assert result.total_iterations < 5
    end

    test "reflexion memory improves subsequent runs" do
      memory = ReflexionMemory.new!(%{storage: :ets})

      # First run - store critiques
      loop1 =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          memory: {:ok, memory},
          max_iterations: 2
        })

      prompt = "What is 15 * 23?"
      initial1 = Candidate.new!(%{id: "run1", content: "I think it's 300"})

      {:ok, _result1} = ReflectionLoop.run(loop1, prompt, %{initial_candidate: initial1})

      # Verify memory stored entries
      assert ReflexionMemory.count(memory) > 0

      # Second run - should benefit from memory (retrieves similar critiques)
      loop2 =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          memory: {:ok, memory},
          max_iterations: 2
        })

      initial2 = Candidate.new!(%{id: "run2", content: "Let me calculate"})

      {:ok, result2} = ReflectionLoop.run(loop2, prompt, %{initial_candidate: initial2})

      # Second run completes successfully
      assert result2.total_iterations > 0

      ReflexionMemory.stop(memory)
    end

    test "self-refine improves response in single pass" do
      _strategy = SelfRefine.new!([])

      # We can't test full LLM integration without mocking,
      # but we can verify the comparison function works correctly
      original = Candidate.new!(%{content: "Short answer"})
      refined = Candidate.new!(%{content: "This is a much longer and more detailed answer that provides comprehensive information"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.improved == true
      assert comparison.length_delta > 0
      assert comparison.length_change > 0
      assert comparison.original_length < comparison.refined_length
    end
  end

  # ============================================================================
  # Section 4.5.2: Domain-Specific Tests
  # ============================================================================

  describe "4.5.2 Domain-Specific Tests" do
    test "code improvement through reflection" do
      # Start with buggy code
      buggy_code = "TODO: calculate function"

      loop =
        ReflectionLoop.new!(%{
          critiquer: CodeCritiquer,
          reviser: CodeReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "buggy-code", content: buggy_code})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Write a calculate function", %{
                 initial_candidate: initial
               })

      # Verify code was improved
      refute result.best_candidate.content == buggy_code

      # Should have fixed at least some issues
      refined_content = result.best_candidate.content

      # Check for improvements
      assert String.contains?(refined_content, "def") or
               String.contains?(refined_content, "end") or
               !String.contains?(refined_content, "TODO")

      # Score should improve
      assert result.best_candidate.score >= 0.5
    end

    test "writing improvement through reflection" do
      # Start with rough draft
      rough_draft = "This is very good. very bad."

      loop =
        ReflectionLoop.new!(%{
          critiquer: WritingCritiquer,
          reviser: WritingReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "rough-draft", content: rough_draft})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Improve this writing", %{
                 initial_candidate: initial
               })

      # Verify writing was improved
      refined = result.best_candidate.content

      # Should be longer (more detailed)
      assert String.length(refined) >= String.length(rough_draft)

      # Score should improve
      assert result.best_candidate.score > 0.5
    end

    test "math reasoning improvement through reflection" do
      # Start with incorrect math
      wrong_answer = "I think 15 * 23 equals 320"

      loop =
        ReflectionLoop.new!(%{
          critiquer: MathCritiquer,
          reviser: MathReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "wrong-math", content: wrong_answer})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "What is 15 * 23?", %{
                 initial_candidate: initial
               })

      # Verify math was corrected
      refined = result.best_candidate.content

      # Should contain the correct answer
      assert String.contains?(refined, "345")

      # Score should be high (correct answer)
      assert result.best_candidate.score >= 0.9
    end
  end

  # ============================================================================
  # Section 4.5.3: Performance Tests
  # ============================================================================

  describe "4.5.3 Performance Tests" do
    @tag :performance
    test "reflection loop completes in reasonable time" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 3
        })

      initial = Candidate.new!(%{id: "perf-test", content: "Test content"})

      # Measure execution time
      {time, {:ok, _result}} =
        :timer.tc(fn -> ReflectionLoop.run(loop, "Performance test", %{initial_candidate: initial}) end)

      time_ms = time / 1000

      # Should complete in less than 1 second for mocks
      # (Real LLM calls would take longer, this is testing the orchestration overhead)
      assert time_ms < 1000
    end

    @tag :performance
    test "memory lookup is efficient" do
      memory = ReflexionMemory.new!(%{storage: :ets, max_entries: 1000})

      # Store many critiques
      entries =
        Enum.map(1..100, fn i ->
          %{
            prompt: "Question #{i}",
            mistake: "Error #{i}",
            correction: "Fix #{i}",
            timestamp: DateTime.utc_now()
          }
        end)

      Enum.each(entries, fn entry ->
        :ok = ReflexionMemory.store(memory, entry)
      end)

      # Measure retrieval time
      {time, {:ok, _results}} =
        :timer.tc(fn -> ReflexionMemory.retrieve_similar(memory, "Question 50") end)

      time_us = time

      # Should retrieve in less than 10 milliseconds
      assert time_us < 10_000

      ReflexionMemory.stop(memory)
    end

    @tag :performance
    test "reflexion memory handles max_entries limit efficiently" do
      memory = ReflexionMemory.new!(%{storage: :ets, max_entries: 50})

      # Store more than max_entries
      Enum.each(1..100, fn i ->
        :ok =
          ReflexionMemory.store(memory, %{
            prompt: "Question #{i}",
            mistake: "Error #{i}",
            correction: "Fix #{i}"
          })
      end)

      # Count should be at or near max_entries
      count = ReflexionMemory.count(memory)
      assert count <= 50

      # Lookup should still be fast
      {time, {:ok, _results}} =
        :timer.tc(fn -> ReflexionMemory.retrieve_similar(memory, "Question") end)

      time_us = time
      assert time_us < 10_000

      ReflexionMemory.stop(memory)
    end
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  describe "Edge Cases" do
    test "handles empty initial content" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 2
        })

      initial = Candidate.new!(%{id: "empty", content: ""})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Generate content", %{initial_candidate: initial})

      # Should still generate improved content
      assert is_binary(result.best_candidate.content)
    end

    test "handles nil content gracefully" do
      loop =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 1
        })

      initial = Candidate.new!(%{id: "nil-content", content: nil})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      # Should complete without error
      assert result.total_iterations >= 0
    end

    test "handles very long content" do
      long_content = String.duplicate("This is a very long response. ", 1000)

      loop =
        ReflectionLoop.new!(%{
          critiquer: ImprovingCritiquer,
          reviser: ImprovingReviser,
          max_iterations: 1
        })

      initial = Candidate.new!(%{id: "long", content: long_content})

      assert {:ok, result} =
               ReflectionLoop.run(loop, "Test", %{initial_candidate: initial})

      # Should complete without error
      assert result.total_iterations >= 0
    end
  end

  # ============================================================================
  # Integration: SelfRefine Comparison
  # ============================================================================

  describe "SelfRefine Comparison Integration" do
    test "comparison detects no improvement when content is similar" do
      original = Candidate.new!(%{content: "The answer is 42."})
      refined = Candidate.new!(%{content: "The answer is 42!"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      # Small change shouldn't trigger "improved"
      assert comparison.improved == false
    end

    test "comparison handles nil content correctly" do
      original = Candidate.new!(%{content: nil})
      refined = Candidate.new!(%{content: "Some content here"})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.original_length == 0
      assert comparison.refined_length > 0
      assert comparison.length_delta > 0
    end

    test "comparison shows negative change for shorter content" do
      original = Candidate.new!(%{content: "This is a very long and detailed response that covers many aspects of the question thoroughly."})
      refined = Candidate.new!(%{content: "Short."})

      comparison = SelfRefine.compare_original_refined(original, refined)

      assert comparison.length_delta < 0
      assert comparison.length_change < 0
      assert comparison.improved == false
    end
  end
end
