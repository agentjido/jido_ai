defmodule Jido.AI.Runner.GEPA.Diversity.NoveltyScorerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Diversity.{NoveltyScore, NoveltyScorer}

  describe "score_prompt/3" do
    test "scores prompt novelty with empty archive" do
      prompt = "Solve this problem"

      assert {:ok, %NoveltyScore{} = score} = NoveltyScorer.score_prompt(prompt, [])
      assert score.novelty_score == 1.0
      assert score.k_nearest_distance == 1.0
    end

    test "scores prompt novelty with archive" do
      prompt = "New prompt"

      archive = [
        %{text: "Old prompt one"},
        %{text: "Old prompt two"},
        %{text: "Old prompt three"}
      ]

      assert {:ok, score} = NoveltyScorer.score_prompt(prompt, archive)
      assert score.novelty_score >= 0.0
      assert score.novelty_score <= 1.0
      assert is_list(score.behavioral_features)
    end
  end

  describe "score_population/3" do
    test "scores entire population" do
      prompts = ["prompt1", "prompt2", "prompt3"]
      archive = []

      assert {:ok, scores} = NoveltyScorer.score_population(prompts, archive)
      assert length(scores) == 3
      assert Enum.all?(scores, &match?(%NoveltyScore{}, &1))
    end
  end

  describe "update_archive/3" do
    test "updates archive with new prompts" do
      archive = []
      new_prompts = ["new1", "new2"]

      assert {:ok, updated} = NoveltyScorer.update_archive(archive, new_prompts)
      assert length(updated) == 2
    end

    test "maintains max archive size" do
      archive =
        Enum.map(1..45, fn i ->
          %{
            id: "id#{i}",
            text: "prompt#{i}",
            features: [0.1, 0.2, 0.3],
            added_at: DateTime.utc_now()
          }
        end)

      new_prompts = Enum.map(1..10, fn i -> "new#{i}" end)

      assert {:ok, updated} = NoveltyScorer.update_archive(archive, new_prompts, max_size: 50)
      assert length(updated) <= 50
    end
  end

  describe "combine_fitness_novelty/3" do
    test "combines fitness and novelty scores" do
      combined = NoveltyScorer.combine_fitness_novelty(0.8, 0.6, 0.2)
      assert is_float(combined)
      assert combined >= 0.0
      assert combined <= 1.0
      # Should be weighted toward fitness (80%)
      # Mostly influenced by high fitness
      assert combined >= 0.7
    end

    test "combines with different weights" do
      # Equal weight
      combined = NoveltyScorer.combine_fitness_novelty(0.5, 0.5, 0.5)
      assert combined == 0.5
    end
  end
end
