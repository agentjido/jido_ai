defmodule Mix.Tasks.JidoAi.QualityTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoAi.Quality, as: QualityTask

  setup do
    Mix.shell(Mix.Shell.Process)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_ai_quality_task_#{System.unique_integer([:positive, :monotonic])}")
    traceability_file = Path.join(tmp_dir, "00_traceability_matrix.md")
    git_log_file = Path.join(tmp_dir, "git.log")

    File.mkdir_p!(tmp_dir)

    File.write!(
      traceability_file,
      """
      | Story ID | Theme | Story File | Depends On | Exit Signal |
      | --- | --- | --- | --- | --- |
      | ST-OPS-001 | Ops | specs/stories/01_ops_examples_core.md | None | Backlog files and matrix created |
      | ST-OPS-002 | Ops | specs/stories/01_ops_examples_core.md | ST-OPS-001 | `mix precommit` and `mix test.fast` are available |
      | ST-QAL-001 | Final Quality | specs/stories/06_quality.md | ST-OPS-001, ST-OPS-002 | Full stable quality gate passes |
      """
    )

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(tmp_dir)
    end)

    {:ok, traceability_file: traceability_file, git_log_file: git_log_file}
  end

  describe "traceability-only mode" do
    test "passes when story commit coverage is complete", %{
      traceability_file: traceability_file,
      git_log_file: git_log_file
    } do
      File.write!(
        git_log_file,
        """
        feat(story): ST-OPS-001 Story Backlog Scaffolding And Traceability
        feat(story): ST-OPS-002 Repo Precommit And Dual Stable Gates
        feat(story): ST-QAL-001 Full Stable Quality Checkpoint
        """
      )

      messages =
        run_task_with_output([
          "--traceability-only",
          "--traceability-file",
          traceability_file,
          "--git-log-file",
          git_log_file
        ])

      output = format_messages(messages)

      assert output =~ "==> Verifying traceability closure"
      assert output =~ "Traceability closure: PASS"
      assert output =~ "Traceability rows: 3"
      assert output =~ "Story commits: 3"
      assert output =~ "Fast gate total: 0ms"
      assert output =~ "Full gate total: 0ms"
    end

    test "fails when a story row has no matching commit", %{
      traceability_file: traceability_file,
      git_log_file: git_log_file
    } do
      File.write!(
        git_log_file,
        """
        feat(story): ST-OPS-001 Story Backlog Scaffolding And Traceability
        feat(story): ST-OPS-002 Repo Precommit And Dual Stable Gates
        """
      )

      flush_shell_messages()

      assert_raise Mix.Error, ~r/Traceability closure failed/, fn ->
        invoke_task([
          "--traceability-only",
          "--traceability-file",
          traceability_file,
          "--git-log-file",
          git_log_file
        ])
      end
    end

    test "supports allow-missing for in-progress story work", %{
      traceability_file: traceability_file,
      git_log_file: git_log_file
    } do
      File.write!(
        git_log_file,
        """
        feat(story): ST-OPS-001 Story Backlog Scaffolding And Traceability
        feat(story): ST-OPS-002 Repo Precommit And Dual Stable Gates
        """
      )

      messages =
        run_task_with_output([
          "--traceability-only",
          "--traceability-file",
          traceability_file,
          "--git-log-file",
          git_log_file,
          "--allow-missing",
          "ST-QAL-001"
        ])

      output = format_messages(messages)

      assert output =~ "Allowed missing story IDs: ST-QAL-001"
      assert output =~ "Traceability closure: PASS"
    end
  end

  describe "option handling" do
    test "rejects removed --skip-examples flag" do
      flush_shell_messages()

      assert_raise Mix.Error, ~r/Unknown options: --skip-examples/, fn ->
        invoke_task(["--skip-examples"])
      end
    end
  end

  defp run_task_with_output(args) do
    flush_shell_messages()
    invoke_task(args)
    drain_shell_messages()
  end

  defp invoke_task(args) do
    Mix.Task.reenable("jido_ai.quality")
    QualityTask.run(args)
  end

  defp drain_shell_messages(messages \\ []) do
    receive do
      {:mix_shell, level, [message]} ->
        text = IO.chardata_to_string(message)
        drain_shell_messages([{level, text} | messages])
    after
      25 ->
        Enum.reverse(messages)
    end
  end

  defp flush_shell_messages do
    receive do
      {:mix_shell, _, _} -> flush_shell_messages()
    after
      0 -> :ok
    end
  end

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", fn {_level, text} -> text end)
  end
end
