defmodule Depot.Adapter.ETS.VersioningTest do
  use ExUnit.Case, async: true

  alias Depot.Adapter.ETS
  alias Depot.Adapter.ETS.Versioning

  setup do
    name = :"test_ets_versioning_#{:rand.uniform(10000)}"
    {_adapter, config} = ETS.configure(name: name)

    start_supervised!({ETS, config})

    {:ok, config: config}
  end

  describe "commit/3" do
    test "always returns :ok for ETS adapter", %{config: config} do
      assert :ok = Versioning.commit(config, "test message")
      assert :ok = Versioning.commit(config, nil)
      assert :ok = Versioning.commit(config, "test", snapshot: true)
    end
  end

  describe "revisions/3" do
    test "returns empty list when no versions exist", %{config: config} do
      assert {:ok, []} = Versioning.revisions(config, "nonexistent.txt")
    end

    test "lists versions with standardized format", %{config: config} do
      # Create some versions
      {:ok, _v1} = ETS.write_version(config, "test.txt", "version 1", [])
      {:ok, _v2} = ETS.write_version(config, "test.txt", "version 2", [])

      assert {:ok, revisions} = Versioning.revisions(config, "test.txt")
      assert length(revisions) == 2

      # Check format
      revision = List.first(revisions)
      assert Map.has_key?(revision, :revision)
      assert Map.has_key?(revision, :author_name)
      assert Map.has_key?(revision, :author_email)
      assert Map.has_key?(revision, :message)
      assert Map.has_key?(revision, :timestamp)

      assert revision.author_name == "ETS Adapter"
      assert revision.author_email == "ets@depot.local"
      assert is_binary(revision.revision)
      assert %DateTime{} = revision.timestamp
    end

    test "supports limit option", %{config: config} do
      # Create multiple versions
      for i <- 1..5 do
        {:ok, _} = ETS.write_version(config, "test.txt", "version #{i}", [])
      end

      assert {:ok, revisions} = Versioning.revisions(config, "test.txt", limit: 3)
      assert length(revisions) == 3
    end

    test "supports time range filtering", %{config: config} do
      # Create a version
      {:ok, _} = ETS.write_version(config, "test.txt", "version 1", [])

      # Test since filter (future date should return empty)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      assert {:ok, []} = Versioning.revisions(config, "test.txt", since: future)

      # Test until filter (past date should return empty)
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert {:ok, []} = Versioning.revisions(config, "test.txt", until: past)
    end
  end

  describe "read_revision/4" do
    test "reads content from specific version", %{config: config} do
      {:ok, version_id} = ETS.write_version(config, "test.txt", "test content", [])

      assert {:ok, "test content"} = Versioning.read_revision(config, "test.txt", version_id)
    end

    test "returns error for non-existent version", %{config: config} do
      assert {:error, _} = Versioning.read_revision(config, "test.txt", "nonexistent")
    end
  end

  describe "rollback/3" do
    test "rollbacks single file to previous version", %{config: config} do
      # Create version and update file
      {:ok, version_id} = ETS.write_version(config, "test.txt", "original content", [])
      ETS.write(config, "test.txt", "modified content", [])

      # Verify file was modified
      assert {:ok, "modified content"} = ETS.read(config, "test.txt")

      # Rollback to original version
      assert :ok = Versioning.rollback(config, version_id, path: "test.txt")

      # Verify rollback worked
      assert {:ok, "original content"} = ETS.read(config, "test.txt")
    end

    test "returns error for full rollback (unsupported)", %{config: config} do
      {:ok, version_id} = ETS.write_version(config, "test.txt", "content", [])

      assert {:error, :unsupported} = Versioning.rollback(config, version_id)
    end

    test "returns error for rollback of non-existent version", %{config: config} do
      assert {:error, _} = Versioning.rollback(config, "nonexistent", path: "test.txt")
    end
  end
end
