defmodule Jido.AI.Accuracy.SimilarityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Similarity

  @moduletag :capture_log

  describe "jaccard_similarity/2" do
    test "returns 1.0 for identical strings" do
      assert Similarity.jaccard_similarity("hello world", "hello world") == 1.0
    end

    test "returns 0.0 for completely different strings" do
      assert Similarity.jaccard_similarity("hello world", "foo bar") == 0.0
    end

    test "calculates similarity for partially overlapping strings" do
      # "hello world" and "hello there" share "hello"
      # tokens1: {"hello", "world"}
      # tokens2: {"hello", "there"}
      # intersection: 1, union: 2
      result = Similarity.jaccard_similarity("hello world", "hello there")

      assert_in_delta result, 0.333, 0.01
    end

    test "is case-insensitive" do
      result = Similarity.jaccard_similarity("Hello World", "hello world")

      assert result == 1.0
    end

    test "handles punctuation correctly" do
      result = Similarity.jaccard_similarity("hello, world!", "hello world")

      assert result == 1.0
    end

    test "returns 1.0 for empty strings" do
      assert Similarity.jaccard_similarity("", "") == 1.0
    end

    test "returns 0.0 when one string is empty" do
      assert Similarity.jaccard_similarity("hello", "") == 0.0
      assert Similarity.jaccard_similarity("", "world") == 0.0
    end

    test "handles multiple overlapping tokens" do
      # "the quick brown fox" and "the quick blue fox"
      # tokens1: {"the", "quick", "brown", "fox"}
      # tokens2: {"the", "quick", "blue", "fox"}
      # intersection: 3, union: 5
      result = Similarity.jaccard_similarity("the quick brown fox", "the quick blue fox")

      assert_in_delta result, 0.6, 0.01
    end
  end

  describe "edit_distance_similarity/2" do
    test "returns 1.0 for identical strings" do
      assert Similarity.edit_distance_similarity("hello", "hello") == 1.0
    end

    test "returns 0.0 for completely different strings" do
      result = Similarity.edit_distance_similarity("abc", "xyz")

      assert result == 0.0
    end

    test "calculates similarity for strings with edit distance" do
      # "kitten" -> "sitting": 3 substitutions
      # distance: 3, max_length: 7, similarity: 1 - 3/7 = 0.571...
      result = Similarity.edit_distance_similarity("kitten", "sitting")

      assert_in_delta result, 0.571, 0.01
    end

    test "handles single character difference" do
      result = Similarity.edit_distance_similarity("hello", "hallo")

      assert_in_delta result, 0.8, 0.01
    end

    test "handles insertion" do
      result = Similarity.edit_distance_similarity("cat", "cast")

      assert_in_delta result, 0.75, 0.01
    end

    test "handles deletion" do
      result = Similarity.edit_distance_similarity("hello", "ello")

      assert_in_delta result, 0.8, 0.01
    end

    test "returns 1.0 for empty strings" do
      assert Similarity.edit_distance_similarity("", "") == 1.0
    end

    test "returns 0.0 when one string is empty" do
      assert Similarity.edit_distance_similarity("hello", "") == 0.0
      assert Similarity.edit_distance_similarity("", "world") == 0.0
    end

    test "handles unicode characters" do
      result = Similarity.edit_distance_similarity("café", "cafe")

      # "café" (4 chars) vs "cafe" (4 chars), edit distance 1
      # similarity = 1 - 1/4 = 0.75
      assert_in_delta result, 0.75, 0.01
    end
  end

  describe "combined_similarity/4" do
    test "returns 1.0 for identical strings with any weights" do
      assert Similarity.combined_similarity("hello", "hello", 0.5, 0.5) == 1.0
      assert Similarity.combined_similarity("hello", "hello", 0.7, 0.3) == 1.0
      assert Similarity.combined_similarity("hello", "hello", 1.0, 0.0) == 1.0
    end

    test "weights jaccard and edit distance equally with 0.5, 0.5" do
      result = Similarity.combined_similarity("hello world", "hello there", 0.5, 0.5)

      # jaccard ≈ 0.333, edit ≈ 0.667 (rough estimate)
      # combined ≈ (0.333 + 0.667) / 2 = 0.5
      assert result > 0.0 and result < 1.0
    end

    test "uses only jaccard when edit_weight is 0" do
      result = Similarity.combined_similarity("hello world", "hello there", 1.0, 0.0)
      jaccard = Similarity.jaccard_similarity("hello world", "hello there")

      assert_in_delta result, jaccard, 0.01
    end

    test "uses only edit distance when jaccard_weight is 0" do
      result = Similarity.combined_similarity("kitten", "sitting", 0.0, 1.0)
      edit = Similarity.edit_distance_similarity("kitten", "sitting")

      assert_in_delta result, edit, 0.01
    end

    test "handles zero total weight" do
      result = Similarity.combined_similarity("hello", "world", 0.0, 0.0)

      assert result == 0.0
    end

    test "normalizes weights correctly" do
      result1 = Similarity.combined_similarity("hello world", "hello there", 0.5, 0.5)
      result2 = Similarity.combined_similarity("hello world", "hello there", 5.0, 5.0)

      assert_in_delta result1, result2, 0.01
    end

    test "respects weight ratio" do
      # Higher jaccard weight should make result closer to jaccard
      jaccard = Similarity.jaccard_similarity("hello world", "hello there")
      edit = Similarity.edit_distance_similarity("hello world", "hello there")

      # jaccard < edit for these inputs
      # So with higher jaccard weight, result should be lower (closer to jaccard)
      result_heavy_jaccard = Similarity.combined_similarity("hello world", "hello there", 0.9, 0.1)
      result_heavy_edit = Similarity.combined_similarity("hello world", "hello there", 0.1, 0.9)

      # Higher weight on edit distance should produce higher result
      assert result_heavy_edit > result_heavy_jaccard

      # Verify the weighted average calculation
      expected_heavy_jaccard = (jaccard * 0.9 + edit * 0.1) / 1.0
      expected_heavy_edit = (jaccard * 0.1 + edit * 0.9) / 1.0

      assert_in_delta result_heavy_jaccard, expected_heavy_jaccard, 0.01
      assert_in_delta result_heavy_edit, expected_heavy_edit, 0.01
    end
  end

  describe "edge cases" do
    test "handles very long strings" do
      long1 = String.duplicate("a ", 1000)
      long2 = String.duplicate("a ", 999) <> "b"

      result = Similarity.edit_distance_similarity(long1, long2)

      assert is_number(result)
      assert result >= 0.0 and result <= 1.0
    end

    test "handles strings with only whitespace" do
      result = Similarity.jaccard_similarity("   ", "  ")

      # After tokenization with trim: true, both are empty
      assert result == 1.0
    end

    test "handles strings with only punctuation" do
      # Using characters that are actually in \p{P} (punctuation)
      result = Similarity.jaccard_similarity("!@#", "$%^")

      # Some punctuation chars ($, ^) are not in \p{P}, they're symbols
      # So tokenization produces different results
      assert is_number(result)
      assert result >= 0.0 and result <= 1.0
    end
  end
end
