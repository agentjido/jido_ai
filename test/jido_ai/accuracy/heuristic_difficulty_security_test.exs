defmodule Jido.AI.Accuracy.HeuristicDifficultySecurityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{DifficultyEstimate, Estimators.HeuristicDifficulty}

  @moduletag :security
  @moduletag :heuristic_difficulty

  describe "query length limits" do
    setup do
      estimator = HeuristicDifficulty.new!(%{})
      %{estimator: estimator}
    end

    test "rejects queries exceeding max length (50KB)", %{estimator: estimator} do
      # Max query length is 50_000 bytes
      long_query = String.duplicate("a", 51_000)

      assert {:error, :query_too_long} =
               HeuristicDifficulty.estimate(estimator, long_query, %{})
    end

    test "accepts queries at max length boundary", %{estimator: estimator} do
      boundary_query = String.duplicate("a", 49_999)

      assert {:ok, %DifficultyEstimate{}} =
               HeuristicDifficulty.estimate(estimator, boundary_query, %{})
    end

    test "accepts normal-sized queries", %{estimator: estimator} do
      normal_query = String.duplicate("test ", 100)

      assert {:ok, %DifficultyEstimate{}} =
               HeuristicDifficulty.estimate(estimator, normal_query, %{})
    end
  end

  describe "empty query handling" do
    setup do
      estimator = HeuristicDifficulty.new!(%{})
      %{estimator: estimator}
    end

    test "rejects empty string query", %{estimator: estimator} do
      assert {:error, :invalid_query} = HeuristicDifficulty.estimate(estimator, "", %{})
    end

    test "rejects whitespace-only query", %{estimator: estimator} do
      assert {:error, :invalid_query} =
               HeuristicDifficulty.estimate(estimator, "   \n\t  ", %{})
    end
  end

  describe "input validation" do
    test "rejects non-binary query input" do
      estimator = HeuristicDifficulty.new!(%{})

      assert {:error, :invalid_query} = HeuristicDifficulty.estimate(estimator, 123, %{})
      assert {:error, :invalid_query} = HeuristicDifficulty.estimate(estimator, nil, %{})
      assert {:error, :invalid_query} = HeuristicDifficulty.estimate(estimator, %{}, %{})
    end
  end

  describe "special character handling" do
    setup do
      estimator = HeuristicDifficulty.new!(%{})
      %{estimator: estimator}
    end

    test "handles queries with many special characters", %{estimator: estimator} do
      # Query with many special characters (potential regex DoS)
      special_query = String.duplicate("!@#$%^&*()_+-=[]{}|;':\",./<>?", 100)

      assert {:ok, %DifficultyEstimate{}} =
               HeuristicDifficulty.estimate(estimator, special_query, %{})
    end

    test "handles queries with Unicode characters", %{estimator: estimator} do
      unicode_query = "What is 日本語 and 中文 and 한국어?"

      assert {:ok, %DifficultyEstimate{}} =
               HeuristicDifficulty.estimate(estimator, unicode_query, %{})
    end

    test "handles queries with emojis", %{estimator: estimator} do
      emoji_query = "What does 🤔 💭 🧠 mean?"

      assert {:ok, %DifficultyEstimate{}} =
               HeuristicDifficulty.estimate(estimator, emoji_query, %{})
    end
  end

  describe "custom indicators validation" do
    test "accepts valid custom indicators map" do
      assert %HeuristicDifficulty{} =
               HeuristicDifficulty.new!(%{
                 custom_indicators: %{
                   physics: ["quantum", "entanglement"],
                   chemistry: ["reaction", "molecule"]
                 }
               })
    end

    test "handles empty custom indicators" do
      assert %HeuristicDifficulty{} =
               HeuristicDifficulty.new!(%{custom_indicators: %{}})
    end
  end
end
