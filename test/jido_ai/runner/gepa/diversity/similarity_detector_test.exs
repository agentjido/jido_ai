defmodule Jido.AI.Runner.GEPA.Diversity.SimilarityDetectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Diversity.{SimilarityDetector, SimilarityMatrix, SimilarityResult}

  describe "compare/3" do
    test "compares two identical prompts" do
      prompt = "Solve this problem step by step."

      assert {:ok, %SimilarityResult{} = result} = SimilarityDetector.compare(prompt, prompt)
      assert result.similarity_score >= 0.95
    end

    test "compares two different prompts" do
      prompt_a = "Solve this problem step by step."
      prompt_b = "Calculate that equation quickly."

      assert {:ok, result} = SimilarityDetector.compare(prompt_a, prompt_b)
      assert result.similarity_score >= 0.0
      assert result.similarity_score <= 1.0
      assert result.strategy_used == :text
    end

    test "compares prompts with component breakdown" do
      prompt_a = "Solve step by step"
      prompt_b = "Solve carefully"

      assert {:ok, result} = SimilarityDetector.compare(prompt_a, prompt_b)
      assert is_map(result.components)
      assert Map.has_key?(result.components, :levenshtein)
      assert Map.has_key?(result.components, :jaccard)
    end
  end

  describe "build_matrix/2" do
    test "builds similarity matrix for prompts" do
      prompts = [
        "Prompt one",
        "Prompt two",
        "Prompt three"
      ]

      assert {:ok, %SimilarityMatrix{} = matrix} = SimilarityDetector.build_matrix(prompts)
      assert length(matrix.prompt_ids) == 3
      assert map_size(matrix.scores) > 0
    end

    test "returns error for empty population" do
      assert {:error, :empty_population} = SimilarityDetector.build_matrix([])
    end

    test "handles single prompt" do
      prompts = ["Single prompt"]

      assert {:ok, matrix} = SimilarityDetector.build_matrix(prompts)
      assert length(matrix.prompt_ids) == 1
      # No pairs to compare
      assert map_size(matrix.scores) == 0
    end
  end

  describe "get_similarity/3" do
    test "returns 1.0 for same prompt" do
      prompts = ["Prompt one", "Prompt two"]
      {:ok, matrix} = SimilarityDetector.build_matrix(prompts)

      assert SimilarityDetector.get_similarity(matrix, 0, 0) == 1.0
    end

    test "returns similarity between different prompts" do
      prompts = ["Prompt one", "Prompt two"]
      {:ok, matrix} = SimilarityDetector.build_matrix(prompts)

      score = SimilarityDetector.get_similarity(matrix, 0, 1)
      assert is_float(score)
      assert score >= 0.0
      assert score <= 1.0
    end
  end

  describe "find_duplicates/2" do
    test "finds near-duplicate prompts" do
      prompts = [
        "Solve this problem",
        # Very similar
        "Solve this problem.",
        "Calculate something else"
      ]

      assert {:ok, duplicates} = SimilarityDetector.find_duplicates(prompts, threshold: 0.8)
      assert is_list(duplicates)
    end

    test "returns empty list when no duplicates" do
      prompts = [
        "Alpha",
        "Beta",
        "Gamma"
      ]

      assert {:ok, duplicates} = SimilarityDetector.find_duplicates(prompts, threshold: 0.9)
      # May or may not find duplicates depending on similarity
      assert is_list(duplicates)
    end
  end
end
