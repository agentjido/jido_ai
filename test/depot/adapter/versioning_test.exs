defmodule Depot.Adapter.VersioningTest do
  use ExUnit.Case, async: true

  alias Depot.Adapter.Versioning

  setup_all do
    # Ensure all modules are loaded for function_exported? checks
    Code.ensure_loaded(Depot.Adapter.Git)
    Code.ensure_loaded(Depot.Adapter.ETS.Versioning)
    Code.ensure_loaded(Depot.Adapter.InMemory.Versioning)
    :ok
  end

  describe "versioning_supported?/1" do
    test "returns true for Git adapter" do
      assert Versioning.versioning_supported?(Depot.Adapter.Git)
    end

    test "returns true for ETS versioning wrapper" do
      assert Versioning.versioning_supported?(Depot.Adapter.ETS.Versioning)
    end

    test "returns true for InMemory versioning wrapper" do
      assert Versioning.versioning_supported?(Depot.Adapter.InMemory.Versioning)
    end

    test "returns false for non-versioning adapters" do
      refute Versioning.versioning_supported?(Depot.Adapter.Local)
      refute Versioning.versioning_supported?(Depot.Adapter.S3)
    end

    test "returns false for non-existent modules" do
      refute Versioning.versioning_supported?(NonExistentModule)
    end
  end

  describe "supported_operations/1" do
    test "returns all operations for Git adapter" do
      operations = Versioning.supported_operations(Depot.Adapter.Git)

      assert :commit in operations
      assert :revisions in operations
      assert :read_revision in operations
      assert :rollback in operations
    end

    test "returns basic operations for ETS versioning wrapper" do
      operations = Versioning.supported_operations(Depot.Adapter.ETS.Versioning)

      assert :commit in operations
      assert :revisions in operations
      assert :read_revision in operations
      assert :rollback in operations
    end

    test "returns basic operations for InMemory versioning wrapper" do
      operations = Versioning.supported_operations(Depot.Adapter.InMemory.Versioning)

      assert :commit in operations
      assert :revisions in operations
      assert :read_revision in operations
      assert :rollback in operations
    end

    test "returns empty list for non-versioning adapters" do
      assert [] = Versioning.supported_operations(Depot.Adapter.Local)
      assert [] = Versioning.supported_operations(Depot.Adapter.S3)
    end
  end
end
