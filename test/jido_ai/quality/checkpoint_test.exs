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

  describe "full_gate_commands/0" do
    test "includes docs and coverage commands" do
      labels = Checkpoint.full_gate_commands() |> Enum.map(& &1.label)

      assert "mix test --exclude flaky" in labels
      assert "mix doctor --summary" in labels
      assert "mix docs" in labels
      assert "mix coveralls" in labels
    end
  end

  describe "fast_gate_commands/0" do
    test "includes mix precommit command" do
      assert [%{gate: :fast, label: "mix precommit", cmd: "mix", args: ["precommit"]}] =
               Checkpoint.fast_gate_commands()
    end
  end

  describe "run_command/2" do
    test "returns timing on success" do
      command = %{gate: :fast, label: "ok", cmd: "sh", args: ["-c", "exit 0"]}

      assert {:ok, %{gate: :fast, label: "ok", elapsed_ms: elapsed_ms}} =
               Checkpoint.run_command(command)

      assert is_integer(elapsed_ms)
      assert elapsed_ms >= 0
    end

    test "returns failure details on non-zero exit" do
      command = %{gate: :full, label: "fail", cmd: "sh", args: ["-c", "exit 7"]}

      assert {:error, failure} = Checkpoint.run_command(command)
      assert failure.gate == :full
      assert failure.label == "fail"
      assert failure.cmd == "sh"
      assert failure.args == ["-c", "exit 7"]
      assert failure.status == 7
      assert is_integer(failure.elapsed_ms)
    end
  end

  describe "run_commands/2" do
    test "returns timings in command order when all commands pass" do
      commands = [
        %{gate: :fast, label: "first", cmd: "sh", args: ["-c", "exit 0"]},
        %{gate: :full, label: "second", cmd: "sh", args: ["-c", "exit 0"]}
      ]

      assert {:ok, [first, second]} = Checkpoint.run_commands(commands)
      assert first.label == "first"
      assert second.label == "second"
    end

    test "halts and returns first failure" do
      commands = [
        %{gate: :fast, label: "pass", cmd: "sh", args: ["-c", "exit 0"]},
        %{gate: :full, label: "fail", cmd: "sh", args: ["-c", "exit 3"]},
        %{gate: :full, label: "not-run", cmd: "sh", args: ["-c", "exit 0"]}
      ]

      assert {:error, failure} = Checkpoint.run_commands(commands)
      assert failure.label == "fail"
      assert failure.status == 3
    end
  end

  describe "read_traceability_story_ids/1" do
    test "reads IDs from a matrix file" do
      path = Path.join(System.tmp_dir!(), "traceability-#{System.unique_integer([:positive])}.md")

      File.write!(
        path,
        """
        | Story ID | Theme |
        | --- | --- |
        | ST-OPS-001 | Ops |
        | ST-QAL-001 | Quality |
        """
      )

      on_exit(fn -> File.rm(path) end)

      assert {:ok, ["ST-OPS-001", "ST-QAL-001"]} = Checkpoint.read_traceability_story_ids(path)
    end

    test "returns file read error for missing file" do
      path = Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}.md")
      assert {:error, :enoent} = Checkpoint.read_traceability_story_ids(path)
    end
  end

  describe "read_story_commit_ids/1" do
    test "reads commit subjects from current repository" do
      assert {:ok, ids} = Checkpoint.read_story_commit_ids(".")
      assert is_list(ids)
    end

    test "returns structured error when git log fails" do
      tmp_repo = Path.join(System.tmp_dir!(), "non-git-repo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_repo)
      on_exit(fn -> File.rmdir(tmp_repo) end)

      assert {:error, {:git_log_failed, status, _output}} = Checkpoint.read_story_commit_ids(tmp_repo)
      assert is_integer(status)
      assert status != 0
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
