defmodule Jido.AI.RLM.ContextStoreTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.ContextStore

  @small_data "hello world"
  @large_data String.duplicate("x", 3_000_000)

  describe "inline tier" do
    test "put/fetch/delete cycle" do
      {:ok, ref} = ContextStore.put(@small_data, "req-1")
      assert ref.backend == :inline
      assert {:ok, @small_data} == ContextStore.fetch(ref)
      assert :ok == ContextStore.delete(ref)
    end

    test "fetch_range returns a slice" do
      {:ok, ref} = ContextStore.put("abcdefghij", "req-2")
      assert {:ok, "cdef"} == ContextStore.fetch_range(ref, 2, 4)
    end

    test "size returns byte size" do
      {:ok, ref} = ContextStore.put(@small_data, "req-3")
      assert ContextStore.size(ref) == byte_size(@small_data)
    end
  end

  describe "ets tier" do
    test "put/fetch/delete cycle with large data" do
      {:ok, ref} = ContextStore.put(@large_data, "req-4")
      assert ref.backend == :ets
      assert {:ok, @large_data} == ContextStore.fetch(ref)
      assert :ok == ContextStore.delete(ref)
    end

    test "put/fetch/delete cycle forced by small threshold" do
      {:ok, ref} = ContextStore.put("small", "req-5", inline_threshold: 1)
      assert ref.backend == :ets
      assert {:ok, "small"} == ContextStore.fetch(ref)
      assert :ok == ContextStore.delete(ref)
    end

    test "fetch_range returns a slice" do
      {:ok, ref} = ContextStore.put("abcdefghij", "req-6", inline_threshold: 1)
      assert {:ok, "cdef"} == ContextStore.fetch_range(ref, 2, 4)
    end

    test "size returns byte size" do
      {:ok, ref} = ContextStore.put(@large_data, "req-7")
      assert ContextStore.size(ref) == byte_size(@large_data)
    end

    test "accepts existing ETS table" do
      table = :ets.new(:custom, [:set, :private])
      {:ok, ref} = ContextStore.put("data", "req-8", inline_threshold: 1, table: table)
      assert ref.table == table
      assert {:ok, "data"} == ContextStore.fetch(ref)
    end
  end

  describe "workspace tier" do
    test "put/fetch/delete cycle with workspace ref" do
      {:ok, ws_ref} = Jido.AI.RLM.Workspace.init("ws-ctx-1")
      {:ok, ref} = ContextStore.put(@large_data, "req-ws-1", workspace_ref: ws_ref)
      assert ref.backend == :workspace
      assert {:ok, @large_data} == ContextStore.fetch(ref)
      assert :ok == ContextStore.delete(ref)
      Jido.AI.RLM.Workspace.destroy(ws_ref)
    end

    test "fetch_range with workspace ref" do
      {:ok, ws_ref} = Jido.AI.RLM.Workspace.init("ws-ctx-2")
      {:ok, ref} = ContextStore.put("abcdefghij", "req-ws-2", inline_threshold: 1, workspace_ref: ws_ref)
      assert {:ok, "cdef"} == ContextStore.fetch_range(ref, 2, 4)
      Jido.AI.RLM.Workspace.destroy(ws_ref)
    end

    test "size with workspace ref" do
      {:ok, ws_ref} = Jido.AI.RLM.Workspace.init("ws-ctx-3")
      {:ok, ref} = ContextStore.put(@large_data, "req-ws-3", workspace_ref: ws_ref)
      assert ContextStore.size(ref) == byte_size(@large_data)
      Jido.AI.RLM.Workspace.destroy(ws_ref)
    end
  end

  describe "tier selection" do
    test "data below threshold uses inline" do
      {:ok, ref} = ContextStore.put("tiny", "req-9", inline_threshold: 100)
      assert ref.backend == :inline
    end

    test "data at threshold uses ets" do
      data = String.duplicate("a", 100)
      {:ok, ref} = ContextStore.put(data, "req-10", inline_threshold: 100)
      assert ref.backend == :ets
    end

    test "data above threshold uses ets" do
      data = String.duplicate("a", 200)
      {:ok, ref} = ContextStore.put(data, "req-11", inline_threshold: 100)
      assert ref.backend == :ets
    end
  end

  describe "fetch after delete" do
    test "inline fetch after delete still returns data (immutable ref)" do
      {:ok, ref} = ContextStore.put("kept", "req-12")
      :ok = ContextStore.delete(ref)
      assert {:ok, "kept"} == ContextStore.fetch(ref)
    end

    test "ets fetch after delete returns error" do
      {:ok, ref} = ContextStore.put("gone", "req-13", inline_threshold: 1)
      :ok = ContextStore.delete(ref)
      assert {:error, :not_found} == ContextStore.fetch(ref)
    end

    test "ets fetch_range after delete returns error" do
      {:ok, ref} = ContextStore.put("gone", "req-14", inline_threshold: 1)
      :ok = ContextStore.delete(ref)
      assert {:error, :not_found} == ContextStore.fetch_range(ref, 0, 1)
    end
  end
end
