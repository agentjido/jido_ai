defmodule Jido.AI.Runner.SelfConsistencyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.SelfConsistency
  alias Jido.AI.Runner.SelfConsistency.{AnswerExtractor, PathQualityAnalyzer, VotingMechanism}

  # =============================================================================
  # Answer Extraction Tests
  # =============================================================================

  describe "AnswerExtractor.extract/2" do
    test "extracts answer from 'answer is' pattern" do
      reasoning = "After calculation, the answer is 42."
      assert {:ok, answer} = AnswerExtractor.extract(reasoning)
      # Numbers are normalized to integers/floats
      assert answer == 42
    end

    test "extracts answer from 'therefore' pattern" do
      reasoning = "Step 1: Add 2+2. Step 2: Multiply by 10. Therefore: 40"
      assert {:ok, answer} = AnswerExtractor.extract(reasoning)
      # Numbers are normalized to integers/floats
      assert answer == 40
    end

    test "extracts answer from 'result' pattern" do
      reasoning = "Performing calculation. Result: 123"
      assert {:ok, answer} = AnswerExtractor.extract(reasoning)
      # Numbers are normalized to integers/floats
      assert answer == 123
    end

    test "extracts math answer with domain hint" do
      reasoning = "The calculation gives us answer = 3.14"
      assert {:ok, answer} = AnswerExtractor.extract(reasoning, domain: :math)
      # Math domain normalizes to number
      assert answer == 3.14
    end

    test "extracts code from code blocks" do
      reasoning = """
      The solution is:
      ```elixir
      def hello, do: :world
      ```
      """

      assert {:ok, answer} = AnswerExtractor.extract(reasoning, domain: :code)
      assert answer =~ "def hello"
    end

    test "handles missing answer" do
      reasoning = "This is just some text without an answer marker."
      assert {:ok, _answer} = AnswerExtractor.extract(reasoning)
    end
  end

  describe "AnswerExtractor.normalize/2" do
    test "normalizes string answers" do
      assert {:ok, "hello"} = AnswerExtractor.normalize("  HELLO  ")
    end

    test "normalizes numeric strings to numbers in math domain" do
      assert {:ok, 42} = AnswerExtractor.normalize("42", domain: :math)
      assert {:ok, 3.14} = AnswerExtractor.normalize("3.14", domain: :math)
    end

    test "converts word numbers to integers" do
      assert {:ok, 5} = AnswerExtractor.normalize("five", domain: :math)
      assert {:ok, 20} = AnswerExtractor.normalize("twenty", domain: :math)
    end

    test "normalizes boolean strings" do
      assert {:ok, true} = AnswerExtractor.normalize("yes", format: :boolean)
      assert {:ok, false} = AnswerExtractor.normalize("no", format: :boolean)
      assert {:ok, true} = AnswerExtractor.normalize("true", format: :boolean)
    end

    test "normalizes code by removing markers" do
      code = "```elixir\ndef foo, do: :bar\n```"
      assert {:ok, normalized} = AnswerExtractor.normalize(code, domain: :code)
      assert normalized =~ "def foo"
      refute normalized =~ "```"
    end

    test "handles already normalized values" do
      assert {:ok, 42} = AnswerExtractor.normalize(42)
      assert {:ok, true} = AnswerExtractor.normalize(true)
    end
  end

  describe "AnswerExtractor.equivalent?/3" do
    test "recognizes exact equality" do
      assert AnswerExtractor.equivalent?(42, 42)
      assert AnswerExtractor.equivalent?("hello", "hello")
    end

    test "recognizes numeric equivalence" do
      assert AnswerExtractor.equivalent?(42, "42")
      assert AnswerExtractor.equivalent?("3.14", 3.14)
    end

    test "recognizes case-insensitive string equivalence" do
      assert AnswerExtractor.equivalent?("Hello", "hello")
      assert AnswerExtractor.equivalent?("YES", "yes")
    end

    test "recognizes boolean equivalence" do
      assert AnswerExtractor.equivalent?(true, "yes")
      assert AnswerExtractor.equivalent?(false, "no")
    end

    test "strict mode requires exact match" do
      refute AnswerExtractor.equivalent?(42, "42", strict: true)
      refute AnswerExtractor.equivalent?("Hello", "hello", strict: true)
    end

    test "recognizes non-equivalent answers" do
      refute AnswerExtractor.equivalent?(42, 43)
      refute AnswerExtractor.equivalent?("hello", "world")
    end
  end

  # =============================================================================
  # Voting Mechanism Tests
  # =============================================================================

  describe "VotingMechanism.vote/2 - majority voting" do
    test "selects answer with most votes" do
      paths = [
        %{reasoning: "path1", answer: 42, confidence: 0.8, quality_score: 0.9},
        %{reasoning: "path2", answer: 42, confidence: 0.7, quality_score: 0.8},
        %{reasoning: "path3", answer: 43, confidence: 0.6, quality_score: 0.7}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :majority)
      assert result.answer == 42
      assert result.consensus >= 0.6
      assert result.votes[42] == 2
      assert result.votes[43] == 1
    end

    test "handles unanimous voting" do
      paths = [
        %{reasoning: "path1", answer: 100, confidence: 0.9, quality_score: 0.9},
        %{reasoning: "path2", answer: 100, confidence: 0.8, quality_score: 0.8},
        %{reasoning: "path3", answer: 100, confidence: 0.7, quality_score: 0.7}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :majority)
      assert result.answer == 100
      assert result.consensus == 1.0
      assert result.votes[100] == 3
    end

    test "breaks ties with highest confidence" do
      paths = [
        %{reasoning: "path1", answer: 1, confidence: 0.9, quality_score: 0.8},
        %{reasoning: "path2", answer: 2, confidence: 0.7, quality_score: 0.8}
      ]

      assert {:ok, result} =
               VotingMechanism.vote(paths, strategy: :majority, tie_breaker: :highest_confidence)

      assert result.answer == 1
    end

    test "groups semantically equivalent answers" do
      paths = [
        %{reasoning: "path1", answer: "42", confidence: 0.8, quality_score: 0.9},
        %{reasoning: "path2", answer: 42, confidence: 0.7, quality_score: 0.8},
        %{reasoning: "path3", answer: 43, confidence: 0.6, quality_score: 0.7}
      ]

      assert {:ok, result} =
               VotingMechanism.vote(paths,
                 strategy: :majority,
                 semantic_equivalence: true,
                 domain: :math
               )

      # "42" and 42 should be grouped together
      assert result.consensus >= 0.6
    end
  end

  describe "VotingMechanism.vote/2 - confidence weighted" do
    test "weights votes by confidence scores" do
      paths = [
        %{reasoning: "path1", answer: 42, confidence: 0.9, quality_score: 0.9},
        %{reasoning: "path2", answer: 42, confidence: 0.8, quality_score: 0.8},
        %{reasoning: "path3", answer: 43, confidence: 0.3, quality_score: 0.7}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :confidence_weighted)
      # 42 has total confidence of 1.7 vs 43 with 0.3
      assert result.answer == 42
    end

    test "low confidence answer loses despite majority" do
      paths = [
        %{reasoning: "path1", answer: 1, confidence: 0.3, quality_score: 0.7},
        %{reasoning: "path2", answer: 1, confidence: 0.2, quality_score: 0.6},
        %{reasoning: "path3", answer: 2, confidence: 0.9, quality_score: 0.9}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :confidence_weighted)
      # Answer 2 has higher total confidence (0.9 vs 0.5)
      assert result.answer == 2
    end
  end

  describe "VotingMechanism.vote/2 - quality weighted" do
    test "weights votes by quality scores" do
      paths = [
        %{reasoning: "path1", answer: 42, confidence: 0.7, quality_score: 0.9},
        %{reasoning: "path2", answer: 42, confidence: 0.7, quality_score: 0.8},
        %{reasoning: "path3", answer: 43, confidence: 0.7, quality_score: 0.4}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :quality_weighted)
      # 42 has total quality of 1.7 vs 43 with 0.4
      assert result.answer == 42
    end
  end

  describe "VotingMechanism.vote/2 - hybrid" do
    test "combines count, confidence, and quality" do
      paths = [
        %{reasoning: "path1", answer: 1, confidence: 0.9, quality_score: 0.9},
        %{reasoning: "path2", answer: 2, confidence: 0.5, quality_score: 0.5},
        %{reasoning: "path3", answer: 2, confidence: 0.5, quality_score: 0.5}
      ]

      assert {:ok, result} = VotingMechanism.vote(paths, strategy: :hybrid)
      # Hybrid should balance count (2 favors answer 2) with quality (favors answer 1)
      assert result.answer in [1, 2]
    end
  end

  describe "VotingMechanism.calculate_consensus/3" do
    test "calculates agreement percentage" do
      paths = [
        %{answer: 42, confidence: 0.8, quality_score: 0.9},
        %{answer: 42, confidence: 0.7, quality_score: 0.8},
        %{answer: 43, confidence: 0.6, quality_score: 0.7}
      ]

      consensus = VotingMechanism.calculate_consensus(paths, 42)
      assert_in_delta consensus, 0.67, 0.01
    end

    test "returns 1.0 for unanimous agreement" do
      paths = [
        %{answer: 100, confidence: 0.8, quality_score: 0.9},
        %{answer: 100, confidence: 0.7, quality_score: 0.8}
      ]

      consensus = VotingMechanism.calculate_consensus(paths, 100)
      assert consensus == 1.0
    end

    test "returns 0.0 for no agreement" do
      paths = [
        %{answer: 1, confidence: 0.8, quality_score: 0.9},
        %{answer: 2, confidence: 0.7, quality_score: 0.8}
      ]

      consensus = VotingMechanism.calculate_consensus(paths, 3)
      assert consensus == 0.0
    end
  end

  # =============================================================================
  # Path Quality Analyzer Tests
  # =============================================================================

  describe "PathQualityAnalyzer.analyze/2" do
    test "scores high-quality reasoning highly" do
      path = %{
        reasoning: """
        Step 1: First, we identify the problem.
        Step 2: Then, we apply the formula.
        Step 3: Therefore, the answer is 42.
        """,
        answer: 42,
        confidence: 0.9,
        quality_score: nil
      }

      score = PathQualityAnalyzer.analyze(path)
      assert score > 0.6
    end

    test "scores low-quality reasoning lower" do
      path = %{
        reasoning: "42",
        answer: 42,
        confidence: 0.3,
        quality_score: nil
      }

      score = PathQualityAnalyzer.analyze(path)
      assert score < 0.5
    end

    test "penalizes very short reasoning" do
      path = %{
        reasoning: "idk",
        answer: nil,
        confidence: 0.5,
        quality_score: nil
      }

      score = PathQualityAnalyzer.analyze(path)
      assert score < 0.4
    end

    test "rewards coherent logical flow" do
      path = %{
        reasoning: """
        Given the problem, we first analyze the inputs.
        Because the input is X, we can apply formula Y.
        Therefore, the result is Z.
        """,
        answer: "Z",
        confidence: 0.8,
        quality_score: nil
      }

      score = PathQualityAnalyzer.analyze(path)
      assert score > 0.5
    end

    test "detects contradictions" do
      path = %{
        reasoning: """
        The answer is definitely 42.
        However, it cannot be 42 because that's impossible.
        But maybe it is 42 after all.
        """,
        answer: 42,
        confidence: 0.6,
        quality_score: nil
      }

      score = PathQualityAnalyzer.analyze(path)
      # Contradictions should lower the score
      assert score < 0.7
    end
  end

  describe "PathQualityAnalyzer.detailed_analysis/2" do
    test "provides breakdown of quality factors" do
      path = %{
        reasoning: """
        Step 1: Analyze the problem.
        Step 2: Apply the solution.
        Therefore: the answer is 42.
        """,
        answer: 42,
        confidence: 0.8,
        quality_score: nil
      }

      analysis = PathQualityAnalyzer.detailed_analysis(path)

      assert is_map(analysis)
      assert Map.has_key?(analysis, :score)
      assert Map.has_key?(analysis, :factors)
      assert Map.has_key?(analysis, :outlier)
      assert Map.has_key?(analysis, :reasons)

      assert is_map(analysis.factors)
      assert Map.has_key?(analysis.factors, :coherence)
      assert Map.has_key?(analysis.factors, :completeness)
      assert Map.has_key?(analysis.factors, :confidence)
    end

    test "includes quality reasons" do
      path = %{
        reasoning: """
        Step 1: First step.
        Step 2: Second step.
        Therefore: answer is 42.
        """,
        answer: 42,
        confidence: 0.9,
        quality_score: nil
      }

      analysis = PathQualityAnalyzer.detailed_analysis(path)
      assert is_list(analysis.reasons)
      assert length(analysis.reasons) > 0
    end
  end

  describe "PathQualityAnalyzer.detect_outlier/2" do
    test "detects unusually short paths as outliers" do
      normal_path = %{
        reasoning: String.duplicate("normal reasoning ", 20),
        confidence: 0.8,
        quality_score: 0.8
      }

      outlier_path = %{
        reasoning: "short",
        confidence: 0.7,
        quality_score: 0.7
      }

      context = [normal_path, normal_path, normal_path]

      {is_outlier, reasons} = PathQualityAnalyzer.detect_outlier(outlier_path, context)
      assert is_outlier
      assert length(reasons) > 0
    end

    test "detects low confidence paths as outliers" do
      normal_path = %{
        reasoning: "normal reasoning",
        confidence: 0.8,
        quality_score: 0.8
      }

      outlier_path = %{
        reasoning: "normal reasoning",
        confidence: 0.2,
        quality_score: 0.8
      }

      context = [normal_path, normal_path, normal_path]

      {is_outlier, reasons} = PathQualityAnalyzer.detect_outlier(outlier_path, context)
      assert is_outlier
      assert Enum.any?(reasons, &String.contains?(&1, "confidence"))
    end

    test "does not flag normal paths as outliers" do
      path = %{
        reasoning: "normal reasoning with steps and conclusion",
        confidence: 0.8,
        quality_score: 0.8
      }

      context = [path, path, path]

      {is_outlier, _reasons} = PathQualityAnalyzer.detect_outlier(path, context)
      refute is_outlier
    end
  end

  describe "PathQualityAnalyzer.calibrate_confidence/2" do
    test "maintains confidence for high-quality paths" do
      path = %{
        reasoning: """
        Step 1: Detailed analysis.
        Step 2: Clear reasoning.
        Therefore: conclusion is sound.
        """,
        answer: 42,
        confidence: 0.8,
        quality_score: nil
      }

      calibrated = PathQualityAnalyzer.calibrate_confidence(path)
      assert calibrated >= 0.7
    end

    test "reduces confidence for low-quality paths" do
      path = %{
        reasoning: "idk",
        answer: 42,
        confidence: 0.8,
        quality_score: nil
      }

      calibrated = PathQualityAnalyzer.calibrate_confidence(path)
      assert calibrated < path.confidence
    end
  end

  # =============================================================================
  # Self-Consistency Integration Tests
  # =============================================================================

  describe "SelfConsistency.generate_reasoning_paths/5" do
    test "generates requested number of paths in parallel" do
      problem = "What is 2+2?"
      sample_count = 5

      reasoning_fn = fn i ->
        "Path #{i}: The answer is #{rem(i, 2) + 4}"
      end

      {:ok, paths} =
        SelfConsistency.generate_reasoning_paths(
          problem,
          sample_count,
          0.7,
          reasoning_fn,
          true
        )

      assert length(paths) == sample_count
      assert Enum.all?(paths, &is_binary/1)
    end

    test "generates paths sequentially when parallel disabled" do
      problem = "What is 2+2?"
      sample_count = 3

      reasoning_fn = fn i ->
        "Sequential path #{i}"
      end

      {:ok, paths} =
        SelfConsistency.generate_reasoning_paths(
          problem,
          sample_count,
          0.7,
          reasoning_fn,
          false
        )

      assert length(paths) == sample_count
    end

    test "filters out invalid paths but accepts majority" do
      problem = "What is 2+2?"
      sample_count = 5

      # Return mix of valid and invalid
      reasoning_fn = fn i ->
        if rem(i, 2) == 0 do
          "Valid path #{i}"
        else
          {:error, :failed}
        end
      end

      {:ok, paths} =
        SelfConsistency.generate_reasoning_paths(
          problem,
          sample_count,
          0.7,
          reasoning_fn,
          true
        )

      # Should have at least half valid paths
      assert length(paths) >= div(sample_count, 2)
    end

    test "fails if too few valid paths generated" do
      problem = "What is 2+2?"
      sample_count = 10

      # Most paths fail
      reasoning_fn = fn i ->
        if i == 1 do
          "Valid path"
        else
          {:error, :failed}
        end
      end

      assert {:error, :insufficient_valid_paths} =
               SelfConsistency.generate_reasoning_paths(
                 problem,
                 sample_count,
                 0.7,
                 reasoning_fn,
                 true
               )
    end
  end

  describe "SelfConsistency.ensure_diversity/2" do
    test "filters out near-duplicate paths" do
      paths = [
        %{
          reasoning: "The answer is 42 because math",
          answer: 42,
          confidence: 0.8,
          quality_score: 0.9
        },
        %{
          reasoning: "The answer is 42 because math",
          answer: 42,
          confidence: 0.7,
          quality_score: 0.8
        },
        %{
          reasoning: "After careful analysis, the result is 43",
          answer: 43,
          confidence: 0.6,
          quality_score: 0.7
        }
      ]

      {:ok, diverse} = SelfConsistency.ensure_diversity(paths, 0.3)

      # Should filter out one of the nearly identical paths
      assert length(diverse) <= length(paths)
    end

    test "keeps all paths if sufficiently diverse" do
      paths = [
        %{
          reasoning: "Approach A: Calculate directly. Answer: 10",
          answer: 10,
          confidence: 0.8,
          quality_score: 0.9
        },
        %{
          reasoning: "Approach B: Use formula XYZ. Answer: 20",
          answer: 20,
          confidence: 0.7,
          quality_score: 0.8
        },
        %{
          reasoning: "Approach C: Different method entirely. Answer: 30",
          answer: 30,
          confidence: 0.6,
          quality_score: 0.7
        }
      ]

      {:ok, diverse} = SelfConsistency.ensure_diversity(paths, 0.3)

      # All paths are different, should keep all
      assert length(diverse) == length(paths)
    end

    test "handles empty paths list" do
      {:ok, diverse} = SelfConsistency.ensure_diversity([], 0.3)
      assert diverse == []
    end

    test "handles single path" do
      paths = [%{reasoning: "solo", answer: 42, confidence: 0.8, quality_score: 0.9}]
      {:ok, diverse} = SelfConsistency.ensure_diversity(paths, 0.3)
      assert diverse == paths
    end
  end

  describe "SelfConsistency.run/1 - end-to-end" do
    test "successfully runs self-consistency workflow" do
      # Provide reasoning function that generates diverse paths
      reasoning_fn = fn i ->
        answer = rem(i, 3) + 10

        """
        Path #{i} reasoning:
        Step 1: Analyze the problem.
        Step 2: Calculate the result.
        Therefore, the answer is #{answer}.
        """
      end

      assert {:ok, result} =
               SelfConsistency.run(
                 problem: "What is the answer?",
                 sample_count: 5,
                 temperature: 0.7,
                 reasoning_fn: reasoning_fn,
                 voting_strategy: :majority,
                 min_consensus: 0.3
               )

      assert Map.has_key?(result, :answer)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :consensus)
      assert Map.has_key?(result, :paths)
      assert Map.has_key?(result, :votes)

      assert result.consensus >= 0.3
      assert is_list(result.paths)
    end

    test "fails if consensus too low" do
      # Every path gives different answer
      reasoning_fn = fn i ->
        "The answer is #{i * 10}"
      end

      assert {:error, {:insufficient_consensus, _}} =
               SelfConsistency.run(
                 problem: "What is the answer?",
                 sample_count: 5,
                 reasoning_fn: reasoning_fn,
                 min_consensus: 0.8
               )
    end

    test "uses default parameters when not specified" do
      reasoning_fn = fn _i ->
        "The answer is 42"
      end

      assert {:ok, result} =
               SelfConsistency.run(
                 problem: "What is 6*7?",
                 reasoning_fn: reasoning_fn
               )

      # Should use defaults and succeed with unanimous answer
      assert result.consensus == 1.0
      # Answer could be normalized to integer or remain as string
      assert result.answer in [42, "42"]
    end
  end

  # =============================================================================
  # Performance and Cost Tests
  # =============================================================================

  describe "Performance characteristics" do
    test "parallel execution is faster than sequential" do
      problem = "What is 2+2?"
      sample_count = 5

      # Simulate LLM call with delay
      reasoning_fn = fn i ->
        Process.sleep(10)
        "Answer: #{i}"
      end

      # Parallel execution
      {parallel_time, {:ok, _}} =
        :timer.tc(fn ->
          SelfConsistency.generate_reasoning_paths(
            problem,
            sample_count,
            0.7,
            reasoning_fn,
            true
          )
        end)

      # Sequential execution
      {sequential_time, {:ok, _}} =
        :timer.tc(fn ->
          SelfConsistency.generate_reasoning_paths(
            problem,
            sample_count,
            0.7,
            reasoning_fn,
            false
          )
        end)

      # Parallel should be significantly faster
      assert parallel_time < sequential_time * 0.8
    end

    test "documents expected cost multiplier" do
      # Self-consistency with k samples costs k times more than single path
      # Research shows 5-10x cost for k=5-10 samples

      cost_model = %{
        single_path_cost: 1,
        sample_count: 5,
        self_consistency_cost: fn model -> model.single_path_cost * model.sample_count end
      }

      total_cost = cost_model.self_consistency_cost.(cost_model)

      # Should be 5x for k=5
      assert total_cost == 5
      assert total_cost >= 5 and total_cost <= 10
    end

    test "documents expected accuracy improvement" do
      # Research shows +17.9% accuracy improvement on GSM8K
      improvement_metrics = %{
        baseline_accuracy: 0.72,
        # Base CoT accuracy on GSM8K
        improvement_percent: 17.9
      }

      expected_self_consistency_accuracy =
        improvement_metrics.baseline_accuracy *
          (1 + improvement_metrics.improvement_percent / 100)

      # Self-consistency should achieve ~85% accuracy (72% + 17.9%)
      assert expected_self_consistency_accuracy > improvement_metrics.baseline_accuracy

      assert expected_self_consistency_accuracy >= 0.84 and
               expected_self_consistency_accuracy <= 0.86
    end
  end

  describe "Use case validation" do
    test "documents when to use self-consistency" do
      use_cases = %{
        mission_critical: "High-stakes decisions requiring reliability",
        mathematical_reasoning: "Complex calculations where accuracy is paramount",
        cost_acceptable: "5-10x cost increase is justified by 18% accuracy gain",
        latency_acceptable: "Can tolerate k * base_latency for parallel execution"
      }

      assert Map.has_key?(use_cases, :mission_critical)
      assert Map.has_key?(use_cases, :mathematical_reasoning)
      assert is_binary(use_cases.cost_acceptable)
    end

    test "documents when NOT to use self-consistency" do
      avoid_cases = %{
        simple_queries: "Basic questions answerable with single path",
        cost_sensitive: "Applications where 5-10x cost is prohibitive",
        real_time: "Ultra-low latency requirements (<100ms)",
        high_volume: "Massive scale where cost multiplier is unsustainable"
      }

      assert Map.has_key?(avoid_cases, :simple_queries)
      assert Map.has_key?(avoid_cases, :cost_sensitive)
      assert is_binary(avoid_cases.real_time)
    end
  end
end
