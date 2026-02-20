defmodule Jido.AI.Quality.CheckpointTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Quality.Checkpoint

  describe "story_ids_from_traceability/1" do
    test "extracts unique sorted story IDs from matrix rows" do
      markdown = """
      | Story ID | Theme |
      | --- | --- |
      | ST-OPS-001 | Ops |
      | ST-STR-001 | Strategies |
      | ST-OPS-001 | Ops Duplicate |
      | ST-ACT-006 | Actions |
      """

      assert Checkpoint.story_ids_from_traceability(markdown) == [
               "ST-ACT-006",
               "ST-OPS-001",
               "ST-STR-001"
             ]
    end
  end

  describe "story_ids_from_git_log/1" do
    test "extracts only feat(story) commit IDs" do
      git_log = """
      feat(story): ST-OPS-001 Story Backlog Scaffolding And Traceability
      fix(runtime): tighten request envelopes
      feat(story): ST-STR-001 ReAct Strategy End-To-End
      feat(story): ST-OPS-001 Story Backlog Scaffolding And Traceability
      """

      assert Checkpoint.story_ids_from_git_log(git_log) == ["ST-OPS-001", "ST-STR-001"]
    end
  end

  describe "verify_traceability/3" do
    test "reports missing story IDs when commit coverage is incomplete" do
      traceability_story_ids = ["ST-OPS-001", "ST-OPS-002", "ST-QAL-001"]
      commit_story_ids = ["ST-OPS-001"]

      assert {:error, result} = Checkpoint.verify_traceability(traceability_story_ids, commit_story_ids)
      assert result.missing_story_ids == ["ST-OPS-002", "ST-QAL-001"]
    end

    test "allows explicit temporary gaps when requested" do
      traceability_story_ids = ["ST-OPS-001", "ST-OPS-002", "ST-QAL-001"]
      commit_story_ids = ["ST-OPS-001"]

      assert {:ok, result} =
               Checkpoint.verify_traceability(traceability_story_ids, commit_story_ids,
                 allow_missing: ["ST-OPS-002", "ST-QAL-001"]
               )

      assert result.missing_story_ids == []
    end
  end

  describe "full_gate_commands/1" do
    test "includes docs, coverage, and example spot-check commands by default" do
      labels = Checkpoint.full_gate_commands() |> Enum.map(& &1.label)

      assert "mix test --exclude flaky" in labels
      assert "mix doctor --summary" in labels
      assert "mix docs" in labels
      assert "mix coveralls" in labels
      assert "mix test (example spot checks)" in labels
    end
  end

  describe "gate_totals/1" do
    test "sums elapsed times by gate" do
      timings = [
        %{gate: :fast, label: "mix precommit", elapsed_ms: 1200},
        %{gate: :full, label: "mix test --exclude flaky", elapsed_ms: 2000},
        %{gate: :full, label: "mix doctor --summary", elapsed_ms: 500}
      ]

      assert Checkpoint.gate_totals(timings) == %{fast: 1200, full: 2500}
    end
  end

  describe "normalize_story_ids/1" do
    test "normalizes and validates story IDs" do
      assert {:ok, ["ST-OPS-001", "ST-QAL-001"]} =
               Checkpoint.normalize_story_ids([" ST-QAL-001 ", "ST-OPS-001", "ST-OPS-001"])

      assert {:error, ["not-a-story"]} = Checkpoint.normalize_story_ids(["not-a-story"])
    end
  end
end
