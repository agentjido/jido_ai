defmodule Depot.VersioningPolymorphismTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  describe "polymorphic versioning API" do
    test "Git adapter works with main Depot API", %{tmp_dir: tmp_dir} do
      git_dir = Path.join(tmp_dir, "git_repo")
      filesystem = Depot.Adapter.Git.configure(path: git_dir, mode: :manual)

      # Test polymorphic API
      Depot.write(filesystem, "test.txt", "initial content")
      assert :ok = Depot.commit(filesystem, "Initial commit")

      assert {:ok, revisions} = Depot.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)
      assert {:ok, "initial content"} = Depot.read_revision(filesystem, "test.txt", revision.sha)
    end

    test "ETS adapter works with main Depot API" do
      name = :"test_ets_poly_#{:rand.uniform(10000)}"
      {adapter, config} = Depot.Adapter.ETS.configure(name: name)
      filesystem = {adapter, config}

      start_supervised!({adapter, config})

      # Create some versioned content first (ETS requires explicit versioning)
      {:ok, _version_id} =
        Depot.Adapter.ETS.write_version(config, "test.txt", "versioned content", [])

      # Test polymorphic API
      assert :ok = Depot.commit(filesystem, "ETS commit")

      assert {:ok, revisions} = Depot.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)

      assert {:ok, "versioned content"} =
               Depot.read_revision(filesystem, "test.txt", revision.revision)

      # Test rollback
      assert :ok = Depot.rollback(filesystem, revision.revision, path: "test.txt")
    end

    test "InMemory adapter works with main Depot API" do
      name = :"test_memory_poly_#{:rand.uniform(10000)}"
      {adapter, config} = Depot.Adapter.InMemory.configure(name: name)
      filesystem = {adapter, config}

      start_supervised!({adapter, config})

      # Create some versioned content first (InMemory requires explicit versioning)
      {:ok, _version_id} =
        Depot.Adapter.InMemory.write_version(config, "test.txt", "versioned content", [])

      # Test polymorphic API
      assert :ok = Depot.commit(filesystem, "InMemory commit")

      assert {:ok, revisions} = Depot.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)

      assert {:ok, "versioned content"} =
               Depot.read_revision(filesystem, "test.txt", revision.revision)

      # Test rollback
      assert :ok = Depot.rollback(filesystem, revision.revision, path: "test.txt")
    end

    test "unsupported adapters return proper errors" do
      {adapter, config} = Depot.Adapter.Local.configure(prefix: System.tmp_dir!())
      filesystem = {adapter, config}

      assert {:error, :unsupported} = Depot.commit(filesystem, "test")
      assert {:error, :unsupported} = Depot.revisions(filesystem, "test.txt")
      assert {:error, :unsupported} = Depot.read_revision(filesystem, "test.txt", "rev")
      assert {:error, :unsupported} = Depot.rollback(filesystem, "rev")
    end

    test "all versioning adapters return consistent format" do
      # Git format (maintains backward compatibility)
      git_dir = System.tmp_dir!() |> Path.join("git_#{:rand.uniform(10000)}")
      git_fs = Depot.Adapter.Git.configure(path: git_dir, mode: :manual)

      Depot.write(git_fs, "test.txt", "git content")
      Depot.commit(git_fs, "Git commit")

      {:ok, git_revisions} = Depot.revisions(git_fs, "test.txt")
      git_revision = List.first(git_revisions)

      # Git should return Depot.Revision struct
      assert %Depot.Revision{} = git_revision
      assert is_binary(git_revision.sha)

      # ETS format (new standardized format)
      ets_name = :"test_ets_format_#{:rand.uniform(10000)}"
      {ets_adapter, ets_config} = Depot.Adapter.ETS.configure(name: ets_name)
      ets_fs = {ets_adapter, ets_config}
      start_supervised!({ets_adapter, ets_config})

      {:ok, _} = Depot.Adapter.ETS.write_version(ets_config, "test.txt", "ets content", [])

      {:ok, ets_revisions} = Depot.revisions(ets_fs, "test.txt")
      ets_revision = List.first(ets_revisions)

      # ETS should return standardized map format
      assert is_map(ets_revision)
      assert Map.has_key?(ets_revision, :revision)
      assert Map.has_key?(ets_revision, :author_name)
      assert Map.has_key?(ets_revision, :timestamp)

      File.rm_rf!(git_dir)
    end
  end
end
