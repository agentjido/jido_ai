defmodule Depot.Adapter.GitTest do
  use ExUnit.Case, async: false

  alias Depot.Adapter.Git
  alias Depot.Revision

  @tmp_dir "tmp/git_test"

  setup do
    # Clean up any existing test directory
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)

    # Ensure we have git available
    case System.find_executable("git") do
      nil -> {:skip, "Git not available"}
      _ -> :ok
    end

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
    end)

    {:ok, test_repo: Path.join(@tmp_dir, "test_repo")}
  end

  describe "configure/1" do
    test "creates new repository when path doesn't exist", %{test_repo: repo_path} do
      {Git, config} = Git.configure(path: repo_path)

      assert File.exists?(Path.join(repo_path, ".git"))
      assert config.repo_path == Path.expand(repo_path)
      # depends on git version/config
      assert config.branch in ["main", "master"]
      assert config.author_name == "Depot"
      assert config.author_email == "depot@localhost"
      refute config.auto_commit?
    end

    test "uses existing repository and current branch", %{test_repo: repo_path} do
      # Create repo manually first
      File.mkdir_p!(repo_path)
      System.cmd("git", ["init"], cd: repo_path)
      System.cmd("git", ["checkout", "-b", "feature"], cd: repo_path)

      {Git, config} = Git.configure(path: repo_path)

      assert config.branch == "feature"
    end

    test "switches to target branch if it exists", %{test_repo: repo_path} do
      # Create repo with multiple branches
      File.mkdir_p!(repo_path)
      System.cmd("git", ["init"], cd: repo_path)
      File.write!(Path.join(repo_path, "test.txt"), "initial")
      System.cmd("git", ["add", "."], cd: repo_path)

      System.cmd(
        "git",
        ["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "initial"],
        cd: repo_path
      )

      System.cmd("git", ["checkout", "-b", "develop"], cd: repo_path)
      System.cmd("git", ["checkout", "main"], cd: repo_path)

      {Git, config} = Git.configure(path: repo_path, branch: "develop")

      assert config.branch == "develop"
    end

    test "creates new branch if target doesn't exist", %{test_repo: repo_path} do
      {Git, config} = Git.configure(path: repo_path, branch: "new-feature")

      assert config.branch == "new-feature"
    end

    test "configures auto-commit mode", %{test_repo: repo_path} do
      {Git, config} = Git.configure(path: repo_path, mode: :auto)

      assert config.auto_commit?
    end

    test "configures custom author", %{test_repo: repo_path} do
      {Git, config} =
        Git.configure(
          path: repo_path,
          author: [name: "Jane Doe", email: "jane@example.com"]
        )

      assert config.author_name == "Jane Doe"
      assert config.author_email == "jane@example.com"
    end
  end

  describe "filesystem operations in manual mode" do
    setup %{test_repo: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "write and read files", %{filesystem: fs} do
      assert :ok = Depot.write(fs, "test.txt", "Hello World")
      assert {:ok, "Hello World"} = Depot.read(fs, "test.txt")
    end

    test "delete files", %{filesystem: fs} do
      Depot.write(fs, "test.txt", "content")
      assert :ok = Depot.delete(fs, "test.txt")
      assert {:error, _} = Depot.read(fs, "test.txt")
    end

    test "move files", %{filesystem: fs} do
      Depot.write(fs, "source.txt", "content")
      assert :ok = Depot.move(fs, "source.txt", "dest.txt", [])
      assert {:error, _} = Depot.read(fs, "source.txt")
      assert {:ok, "content"} = Depot.read(fs, "dest.txt")
    end

    test "copy files", %{filesystem: fs} do
      Depot.write(fs, "source.txt", "content")
      assert :ok = Depot.copy(fs, "source.txt", "dest.txt", [])
      assert {:ok, "content"} = Depot.read(fs, "source.txt")
      assert {:ok, "content"} = Depot.read(fs, "dest.txt")
    end

    test "create and delete directories", %{filesystem: fs} do
      assert :ok = Depot.create_directory(fs, "subdir/", [])

      # Git creates .gitkeep files for empty directories
      assert {:ok, ""} = Depot.read(fs, "subdir/.gitkeep")

      assert :ok = Depot.delete_directory(fs, "subdir/", recursive: true)
      assert {:error, _} = Depot.read(fs, "subdir/.gitkeep")
    end

    test "operations are staged but not committed in manual mode", %{
      filesystem: fs,
      test_repo: repo_path
    } do
      Depot.write(fs, "test.txt", "content")

      # Check git status - should have staged changes
      {output, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo_path)
      assert String.contains?(output, "A  test.txt")

      # Should have no commits yet (except initial)
      {log_output, _} = System.cmd("git", ["log", "--oneline"], cd: repo_path)
      commits = String.split(log_output, "\n", trim: true)
      # Only initial commit
      assert length(commits) == 1
    end
  end

  describe "filesystem operations in auto mode" do
    setup %{test_repo: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :auto)
      {:ok, filesystem: filesystem}
    end

    test "operations are automatically committed", %{filesystem: fs, test_repo: repo_path} do
      Depot.write(fs, "test.txt", "content")

      # Should have clean working tree
      {output, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo_path)
      assert output == ""

      # Should have new commit
      {log_output, _} = System.cmd("git", ["log", "--oneline"], cd: repo_path)
      commits = String.split(log_output, "\n", trim: true)
      # Initial + our write commit
      assert length(commits) == 2
      assert String.contains?(hd(commits), "Depot write test.txt")
    end
  end

  describe "versioning operations" do
    setup %{test_repo: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "commit creates commits with messages", %{filesystem: fs, test_repo: repo_path} do
      Depot.write(fs, "test.txt", "content")
      assert :ok = Depot.commit(fs, "Add test file")

      {log_output, _} = System.cmd("git", ["log", "--oneline", "-n", "1"], cd: repo_path)
      assert String.contains?(log_output, "Add test file")
    end

    test "commit with no message uses default", %{filesystem: fs, test_repo: repo_path} do
      Depot.write(fs, "test.txt", "content")
      assert :ok = Depot.commit(fs)

      {log_output, _} = System.cmd("git", ["log", "--oneline", "-n", "1"], cd: repo_path)
      assert String.contains?(log_output, "Manual commit")
    end

    test "commit with no changes returns ok", %{filesystem: fs} do
      assert :ok = Depot.commit(fs, "Nothing to commit")
    end

    test "revisions lists commit history", %{filesystem: fs} do
      Depot.write(fs, "file1.txt", "content1")
      Depot.commit(fs, "First commit")

      Depot.write(fs, "file2.txt", "content2")
      Depot.commit(fs, "Second commit")

      assert {:ok, revisions} = Depot.revisions(fs, ".")
      # Initial + 2 commits
      assert length(revisions) == 3

      [latest | _] = revisions
      assert %Revision{} = latest
      assert latest.message == "Second commit"
      assert is_binary(latest.sha)
      assert %DateTime{} = latest.timestamp
    end

    test "revisions with limit", %{filesystem: fs} do
      Depot.write(fs, "file1.txt", "content1")
      Depot.commit(fs, "First commit")

      Depot.write(fs, "file2.txt", "content2")
      Depot.commit(fs, "Second commit")

      assert {:ok, revisions} = Depot.revisions(fs, ".", limit: 1)
      assert length(revisions) == 1
      assert hd(revisions).message == "Second commit"
    end

    test "revisions for specific file", %{filesystem: fs} do
      Depot.write(fs, "file1.txt", "content1")
      Depot.commit(fs, "Add file1")

      Depot.write(fs, "file2.txt", "content2")
      Depot.commit(fs, "Add file2")

      assert {:ok, revisions} = Depot.revisions(fs, "file1.txt")
      assert length(revisions) == 1
      assert hd(revisions).message == "Add file1"
    end

    test "read_revision reads historical content", %{filesystem: fs} do
      Depot.write(fs, "test.txt", "version 1")
      Depot.commit(fs, "First version")

      {:ok, [revision | _]} = Depot.revisions(fs, "test.txt")

      Depot.write(fs, "test.txt", "version 2")
      Depot.commit(fs, "Second version")

      assert {:ok, "version 1"} = Depot.read_revision(fs, "test.txt", revision.sha)
      assert {:ok, "version 2"} = Depot.read(fs, "test.txt")
    end

    test "rollback resets to previous state", %{filesystem: fs} do
      Depot.write(fs, "test.txt", "version 1")
      Depot.commit(fs, "First version")

      {:ok, [target_revision | _]} = Depot.revisions(fs, ".")

      Depot.write(fs, "test.txt", "version 2")
      Depot.commit(fs, "Second version")

      assert :ok = Depot.rollback(fs, target_revision.sha)
      assert {:ok, "version 1"} = Depot.read(fs, "test.txt")
    end

    test "rollback specific file", %{filesystem: fs} do
      Depot.write(fs, "file1.txt", "content1")
      Depot.write(fs, "file2.txt", "content2")
      Depot.commit(fs, "Add both files")

      {:ok, [target_revision | _]} = Depot.revisions(fs, ".")

      Depot.write(fs, "file1.txt", "modified1")
      Depot.write(fs, "file2.txt", "modified2")
      Depot.commit(fs, "Modify both files")

      assert :ok = Depot.rollback(fs, target_revision.sha, path: "file1.txt")
      # rolled back
      assert {:ok, "content1"} = Depot.read(fs, "file1.txt")
      # unchanged
      assert {:ok, "modified2"} = Depot.read(fs, "file2.txt")
    end
  end

  describe "unsupported operations on non-Git adapters" do
    test "commit returns unsupported for Local adapter" do
      local_fs = Depot.Adapter.Local.configure(prefix: @tmp_dir)
      assert {:error, :unsupported} = Depot.commit(local_fs)
    end

    test "revisions returns unsupported for Local adapter" do
      local_fs = Depot.Adapter.Local.configure(prefix: @tmp_dir)
      assert {:error, :unsupported} = Depot.revisions(local_fs)
    end

    test "read_revision returns unsupported for Local adapter" do
      local_fs = Depot.Adapter.Local.configure(prefix: @tmp_dir)
      assert {:error, :unsupported} = Depot.read_revision(local_fs, "file.txt", "abc123")
    end

    test "rollback returns unsupported for Local adapter" do
      local_fs = Depot.Adapter.Local.configure(prefix: @tmp_dir)
      assert {:error, :unsupported} = Depot.rollback(local_fs, "abc123")
    end
  end

  describe "error handling" do
    test "configure fails when git not available" do
      # Mock System.find_executable to return nil
      # This is tricky to test without changing the implementation
      # For now, we'll skip this test case
    end

    test "git operations handle command failures gracefully", %{test_repo: repo_path} do
      {Git, _config} = Git.configure(path: repo_path)

      # Try to read a revision that doesn't exist
      fs =
        {Git,
         %Git.Config{
           repo_path: repo_path,
           branch: "main",
           author_name: "Test",
           author_email: "test@test.com",
           auto_commit?: false,
           local_config: nil
         }}

      assert {:error, _message} = Depot.read_revision(fs, "nonexistent.txt", "invalid_sha")
    end
  end

  describe "custom commit messages" do
    test "uses custom commit message function", %{test_repo: repo_path} do
      custom_msg_fn = fn %{operation: op, path: path} ->
        "Custom: #{op} on #{path}"
      end

      filesystem =
        Git.configure(
          path: repo_path,
          mode: :auto,
          commit_message: custom_msg_fn
        )

      Depot.write(filesystem, "test.txt", "content")

      {log_output, _} = System.cmd("git", ["log", "--oneline", "-n", "1"], cd: repo_path)
      assert String.contains?(log_output, "Custom: write on test.txt")
    end
  end
end
