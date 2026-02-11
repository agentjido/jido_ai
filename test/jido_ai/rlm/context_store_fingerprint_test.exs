defmodule Jido.AI.RLM.ContextStoreFingerprintTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore

  describe "put/3 fingerprint" do
    test "inline ref includes fingerprint" do
      data = "small context"
      {:ok, ref} = ContextStore.put(data, "req-fp-1")
      assert Map.has_key?(ref, :fingerprint)
      assert ref.fingerprint == :crypto.hash(:sha256, data)
      assert byte_size(ref.fingerprint) == 32
    end

    test "ets ref includes fingerprint" do
      data = String.duplicate("x", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-2")
      assert ref.backend == :ets
      assert Map.has_key?(ref, :fingerprint)
      assert ref.fingerprint == :crypto.hash(:sha256, data)
    end

    test "workspace ref includes fingerprint" do
      {:ok, ws_ref} = WorkspaceStore.init("req-fp-3")
      data = String.duplicate("y", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-3", workspace_ref: ws_ref)
      assert ref.backend == :workspace
      assert Map.has_key?(ref, :fingerprint)
      assert ref.fingerprint == :crypto.hash(:sha256, data)
    end
  end

  describe "fetch/1 fingerprint validation" do
    test "inline fetch succeeds with matching fingerprint" do
      {:ok, ref} = ContextStore.put("hello", "req-fp-10")
      assert {:ok, "hello"} = ContextStore.fetch(ref)
    end

    test "ets fetch succeeds with matching fingerprint" do
      data = String.duplicate("a", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-11")
      assert {:ok, ^data} = ContextStore.fetch(ref)
    end

    test "workspace fetch succeeds with matching fingerprint" do
      {:ok, ws_ref} = WorkspaceStore.init("req-fp-12")
      data = String.duplicate("b", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-12", workspace_ref: ws_ref)
      assert {:ok, ^data} = ContextStore.fetch(ref)
    end

    test "ets fetch returns fingerprint_mismatch when data tampered" do
      data = String.duplicate("c", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-13")
      assert ref.backend == :ets

      :ets.insert(ref.table, {ref.key, "tampered data"})
      assert {:error, :fingerprint_mismatch} = ContextStore.fetch(ref)
    end

    test "inline fetch returns fingerprint_mismatch when data tampered" do
      {:ok, ref} = ContextStore.put("original", "req-fp-14")
      assert ref.backend == :inline

      tampered_ref = %{ref | data: "tampered"}
      assert {:error, :fingerprint_mismatch} = ContextStore.fetch(tampered_ref)
    end
  end

  describe "backward compatibility" do
    test "old-format inline ref without fingerprint still works" do
      old_ref = %{backend: :inline, data: "legacy data", size_bytes: 11}
      assert {:ok, "legacy data"} = ContextStore.fetch(old_ref)
    end

    test "old-format ets ref without fingerprint still works" do
      table = :ets.new(:legacy_test, [:set, :public])
      key = {"req-fp-20", :context}
      :ets.insert(table, {key, "legacy ets data"})

      old_ref = %{backend: :ets, table: table, key: key, size_bytes: 15}
      assert {:ok, "legacy ets data"} = ContextStore.fetch(old_ref)
    end
  end

  describe "fetch_range/3 with fingerprinted refs" do
    test "fetch_range works with fingerprinted inline ref" do
      {:ok, ref} = ContextStore.put("hello world", "req-fp-30")
      assert {:ok, "hello"} = ContextStore.fetch_range(ref, 0, 5)
    end

    test "fetch_range works with fingerprinted ets ref" do
      data = String.duplicate("z", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-31")
      assert {:ok, slice} = ContextStore.fetch_range(ref, 0, 100)
      assert slice == String.duplicate("z", 100)
    end

    test "fetch_range detects tampered data via fingerprint" do
      data = String.duplicate("d", 3_000_000)
      {:ok, ref} = ContextStore.put(data, "req-fp-32")

      :ets.insert(ref.table, {ref.key, String.duplicate("e", 3_000_000)})
      assert {:error, :fingerprint_mismatch} = ContextStore.fetch_range(ref, 0, 100)
    end
  end
end
