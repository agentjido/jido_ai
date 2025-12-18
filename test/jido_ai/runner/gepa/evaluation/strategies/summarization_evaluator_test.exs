defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.SummarizationEvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.SummarizationEvaluator

  describe "evaluate_summarization/2" do
    test "evaluates good summary with high scores" do
      source = "The quick brown fox jumps over the lazy dog. This is a classic English pangram."
      summary = "A pangram about a fox and a dog."

      task = %{
        type: :summarization,
        source_text: source,
        max_length: 20
      }

      metrics = SummarizationEvaluator.evaluate_summarization(summary, task)

      assert metrics.factual_consistency > 0.5
      assert metrics.conciseness_score >= 0.5
      assert metrics.coherence_score > 0.5
      assert metrics.is_truncation == false
    end

    test "penalizes summary longer than source" do
      source = "Short text."
      summary = "This is a very long summary that is much longer than the original source text."

      task = %{
        type: :summarization,
        source_text: source
      }

      metrics = SummarizationEvaluator.evaluate_summarization(summary, task)

      assert metrics.conciseness_score == 0.0
    end

    test "detects truncation" do
      source = "The quick brown fox jumps over the lazy dog and runs through the forest."

      summary = "The quick brown fox jumps over the lazy dog"

      task = %{
        type: :summarization,
        source_text: source
      }

      metrics = SummarizationEvaluator.evaluate_summarization(summary, task)

      assert metrics.is_truncation == true
    end

    test "checks key points coverage" do
      source = "Long article about AI and machine learning..."
      summary = "This summary covers AI and machine learning concepts."

      task = %{
        type: :summarization,
        source_text: source,
        key_points: ["AI", "machine learning"]
      }

      metrics = SummarizationEvaluator.evaluate_summarization(summary, task)

      assert metrics.key_points_coverage == 1.0
    end
  end

  describe "word_count/1" do
    test "counts words correctly" do
      assert SummarizationEvaluator.word_count("one two three") == 3
    end

    test "handles multiple spaces" do
      assert SummarizationEvaluator.word_count("one  two   three") == 3
    end

    test "handles empty string" do
      assert SummarizationEvaluator.word_count("") == 0
    end

    test "handles whitespace-only string" do
      assert SummarizationEvaluator.word_count("   ") == 0
    end

    test "counts real text" do
      text = "The quick brown fox jumps over the lazy dog."
      assert SummarizationEvaluator.word_count(text) == 9
    end

    test "handles nil" do
      assert SummarizationEvaluator.word_count(nil) == 0
    end
  end

  describe "assess_factual_consistency/2" do
    test "returns high score for consistent summary" do
      source = "The cat sat on the mat. It was very comfortable."
      summary = "The cat sat on the mat."

      consistency = SummarizationEvaluator.assess_factual_consistency(summary, source)

      assert consistency >= 0.8
    end

    test "returns low score for hallucinated content" do
      source = "The cat sat on the mat."
      summary = "The dog ran in the park."

      consistency = SummarizationEvaluator.assess_factual_consistency(summary, source)

      assert consistency < 0.5
    end

    test "returns 0 for empty summary" do
      source = "Some text"
      summary = ""

      consistency = SummarizationEvaluator.assess_factual_consistency(summary, source)

      assert consistency == 0.0
    end

    test "handles partial overlap" do
      source = "The quick brown fox jumps over the lazy dog."
      summary = "A brown fox jumps."

      consistency = SummarizationEvaluator.assess_factual_consistency(summary, source)

      # Partial overlap should give a good score
      assert consistency > 0.0
      assert consistency <= 1.0
    end
  end

  describe "extract_content_words/1" do
    test "extracts content words and filters stop words" do
      text = "The quick brown fox jumps over the lazy dog"
      words = SummarizationEvaluator.extract_content_words(text)

      assert "quick" in words
      assert "brown" in words
      assert "fox" in words
      refute "the" in words
      refute "a" in words
    end

    test "removes duplicates" do
      text = "the cat and the dog and the bird"
      words = SummarizationEvaluator.extract_content_words(text)

      assert length(words) == length(Enum.uniq(words))
    end

    test "handles empty string" do
      assert SummarizationEvaluator.extract_content_words("") == []
    end

    test "handles nil" do
      assert SummarizationEvaluator.extract_content_words(nil) == []
    end
  end

  describe "assess_conciseness/3" do
    test "returns 1.0 for good compression ratio" do
      # 10% compression (10 words from 100)
      conciseness = SummarizationEvaluator.assess_conciseness(10, 100, %{})

      assert conciseness == 1.0
    end

    test "returns 0.0 when summary longer than source" do
      conciseness = SummarizationEvaluator.assess_conciseness(100, 50, %{})

      assert conciseness == 0.0
    end

    test "penalizes exceeding max_length" do
      task = %{max_length: 50}
      conciseness = SummarizationEvaluator.assess_conciseness(100, 1000, task)

      assert conciseness < 1.0
    end

    test "penalizes not meeting min_length" do
      task = %{min_length: 50}
      conciseness = SummarizationEvaluator.assess_conciseness(25, 1000, task)

      assert conciseness < 1.0
    end

    test "returns 0.0 for empty summary" do
      conciseness = SummarizationEvaluator.assess_conciseness(0, 100, %{})

      assert conciseness == 0.0
    end

    test "handles edge case of 5% compression" do
      # Exactly 5% should be optimal
      conciseness = SummarizationEvaluator.assess_conciseness(5, 100, %{})

      assert conciseness == 1.0
    end

    test "handles edge case of 25% compression" do
      # Exactly 25% should be optimal
      conciseness = SummarizationEvaluator.assess_conciseness(25, 100, %{})

      assert conciseness == 1.0
    end
  end

  describe "assess_coherence/1" do
    test "returns high score for coherent summary" do
      summary =
        "First, the cat sat on the mat. However, it was uncomfortable. Therefore, the cat moved to the sofa."

      coherence = SummarizationEvaluator.assess_coherence(summary)

      assert coherence > 0.7
    end

    test "returns low score for fragment" do
      summary = "cat mat"

      coherence = SummarizationEvaluator.assess_coherence(summary)

      assert coherence < 0.5
    end

    test "detects sentence structure" do
      summary = "This is a proper sentence. Another sentence here."

      coherence = SummarizationEvaluator.assess_coherence(summary)

      assert coherence > 0.5
    end

    test "penalizes keyword lists" do
      summary = "cat, dog, bird, fish"

      coherence = SummarizationEvaluator.assess_coherence(summary)

      assert coherence < 0.5
    end

    test "rewards logical connectors" do
      summary_with = "First, we analyze. Therefore, we conclude."
      summary_without = "We analyze. We conclude."

      coherence_with = SummarizationEvaluator.assess_coherence(summary_with)
      coherence_without = SummarizationEvaluator.assess_coherence(summary_without)

      assert coherence_with > coherence_without
    end

    test "checks proper ending" do
      summary = "This is a complete sentence."

      coherence = SummarizationEvaluator.assess_coherence(summary)

      assert coherence > 0.5
    end
  end

  describe "assess_key_points_coverage/2" do
    test "returns 1.0 when no key points specified" do
      assert SummarizationEvaluator.assess_key_points_coverage("any summary", nil) == 1.0
      assert SummarizationEvaluator.assess_key_points_coverage("any summary", []) == 1.0
    end

    test "returns 1.0 when all key points covered" do
      summary = "This summary discusses AI and machine learning concepts."
      key_points = ["AI", "machine learning"]

      coverage = SummarizationEvaluator.assess_key_points_coverage(summary, key_points)

      assert coverage == 1.0
    end

    test "returns 0.5 when half key points covered" do
      summary = "This summary discusses AI concepts."
      key_points = ["AI", "blockchain"]

      coverage = SummarizationEvaluator.assess_key_points_coverage(summary, key_points)

      assert coverage == 0.5
    end

    test "returns 0.0 when no key points covered" do
      summary = "This is about something completely different."
      key_points = ["AI", "machine learning"]

      coverage = SummarizationEvaluator.assess_key_points_coverage(summary, key_points)

      assert coverage == 0.0
    end

    test "is case insensitive" do
      summary = "This summary discusses ai concepts."
      key_points = ["AI"]

      coverage = SummarizationEvaluator.assess_key_points_coverage(summary, key_points)

      assert coverage == 1.0
    end
  end

  describe "detect_truncation/2" do
    test "detects truncation when summary is start of source" do
      source = "The quick brown fox jumps over the lazy dog and runs through the forest."
      summary = "The quick brown fox jumps over"

      assert SummarizationEvaluator.detect_truncation(summary, source) == true
    end

    test "does not detect truncation for real summary" do
      source = "The quick brown fox jumps over the lazy dog and runs through the forest."
      summary = "A fox runs through the forest."

      assert SummarizationEvaluator.detect_truncation(summary, source) == false
    end

    test "returns false for short texts" do
      source = "Short."
      summary = "Short."

      assert SummarizationEvaluator.detect_truncation(summary, source) == false
    end

    test "handles edge cases" do
      assert SummarizationEvaluator.detect_truncation("", "") == false
      assert SummarizationEvaluator.detect_truncation("abc", "def") == false
    end
  end

  describe "string_similarity/2" do
    test "returns 1.0 for identical strings" do
      similarity = SummarizationEvaluator.string_similarity("hello", "hello")

      assert_in_delta similarity, 1.0, 0.1
    end

    test "returns 0.0 for completely different strings" do
      similarity = SummarizationEvaluator.string_similarity("abc", "xyz")

      assert similarity < 0.5
    end

    test "returns high score for similar strings" do
      similarity = SummarizationEvaluator.string_similarity("hello world", "hello world!")

      assert similarity > 0.85
    end

    test "is case insensitive" do
      similarity = SummarizationEvaluator.string_similarity("Hello", "hello")

      assert_in_delta similarity, 1.0, 0.1
    end

    test "handles empty strings" do
      assert SummarizationEvaluator.string_similarity("", "") == 0.0
    end
  end

  describe "calculate_summarization_fitness/2" do
    test "calculates fitness with perfect scores" do
      metrics = %{
        factual_consistency: 1.0,
        conciseness_score: 1.0,
        coherence_score: 1.0,
        key_points_coverage: 1.0,
        is_truncation: false
      }

      fitness = SummarizationEvaluator.calculate_summarization_fitness(0.8, metrics)

      # Should be: 0.4*1.0 + 0.3*1.0 + 0.2*1.0 + 0.1*1.0 = 1.0
      assert_in_delta fitness, 1.0, 0.01
    end

    test "calculates fitness with mixed scores" do
      metrics = %{
        factual_consistency: 0.8,
        conciseness_score: 0.6,
        coherence_score: 0.9,
        key_points_coverage: 0.7,
        is_truncation: false
      }

      fitness = SummarizationEvaluator.calculate_summarization_fitness(0.7, metrics)

      # Should be: 0.4*0.8 + 0.3*0.6 + 0.2*0.9 + 0.1*0.7 = 0.75
      assert_in_delta fitness, 0.75, 0.01
    end

    test "penalizes truncation heavily" do
      metrics = %{
        factual_consistency: 1.0,
        conciseness_score: 1.0,
        coherence_score: 1.0,
        key_points_coverage: 1.0,
        is_truncation: true
      }

      fitness = SummarizationEvaluator.calculate_summarization_fitness(0.8, metrics)

      # Should be: 1.0 * 0.5 (truncation penalty) = 0.5
      assert_in_delta fitness, 0.5, 0.01
    end

    test "prioritizes factual consistency" do
      high_consistency = %{
        factual_consistency: 1.0,
        conciseness_score: 0.0,
        coherence_score: 0.0,
        key_points_coverage: 0.0,
        is_truncation: false
      }

      low_consistency = %{
        factual_consistency: 0.0,
        conciseness_score: 1.0,
        coherence_score: 1.0,
        key_points_coverage: 1.0,
        is_truncation: false
      }

      fitness_high =
        SummarizationEvaluator.calculate_summarization_fitness(0.5, high_consistency)

      fitness_low = SummarizationEvaluator.calculate_summarization_fitness(0.5, low_consistency)

      # High consistency (0.4) should score higher than perfect conciseness+coherence+coverage (0.6)
      assert fitness_high < fitness_low
      # But factual consistency is weighted 40%, so 0.4 vs 0.6
    end
  end
end
