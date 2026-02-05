defmodule Jido.AI.MemoryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Memory
  alias Jido.AI.Memory.Entry

  @table :jido_ai_memory_test

  setup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    {:ok, opts: [table: @table]}
  end

  describe "store/4" do
    test "stores a new entry", %{opts: opts} do
      assert {:ok, %Entry{} = entry} = Memory.store("agent_1", "name", "Alice", opts)
      assert entry.agent_id == "agent_1"
      assert entry.key == "name"
      assert entry.value == "Alice"
      assert entry.tags == []
      assert entry.metadata == %{}
      assert %DateTime{} = entry.inserted_at
    end

    test "stores with tags and metadata", %{opts: opts} do
      opts = Keyword.merge(opts, tags: ["profile", "personal"], metadata: %{source: "user"})
      assert {:ok, %Entry{} = entry} = Memory.store("agent_1", "name", "Alice", opts)
      assert entry.tags == ["profile", "personal"]
      assert entry.metadata == %{source: "user"}
    end

    test "updates existing entry preserving inserted_at", %{opts: opts} do
      {:ok, original} = Memory.store("agent_1", "name", "Alice", opts)
      {:ok, updated} = Memory.store("agent_1", "name", "Bob", opts)

      assert updated.value == "Bob"
      assert updated.inserted_at == original.inserted_at
      assert DateTime.compare(updated.updated_at, original.inserted_at) in [:gt, :eq]
    end

    test "scopes entries per agent", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "name", "Alice", opts)
      {:ok, _} = Memory.store("agent_2", "name", "Bob", opts)

      assert {:ok, %Entry{value: "Alice"}} = Memory.recall("agent_1", %{key: "name"}, opts)
      assert {:ok, %Entry{value: "Bob"}} = Memory.recall("agent_2", %{key: "name"}, opts)
    end
  end

  describe "recall/3 by key" do
    test "returns entry when found", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "color", "blue", opts)
      assert {:ok, %Entry{value: "blue"}} = Memory.recall("agent_1", %{key: "color"}, opts)
    end

    test "returns nil when not found", %{opts: opts} do
      assert {:ok, nil} = Memory.recall("agent_1", %{key: "missing"}, opts)
    end

    test "does not cross agent boundaries", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "secret", "hidden", opts)
      assert {:ok, nil} = Memory.recall("agent_2", %{key: "secret"}, opts)
    end
  end

  describe "recall/3 by tags" do
    test "returns entries matching all tags", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "k1", "v1", Keyword.put(opts, :tags, ["a", "b"]))
      {:ok, _} = Memory.store("agent_1", "k2", "v2", Keyword.put(opts, :tags, ["a"]))
      {:ok, _} = Memory.store("agent_1", "k3", "v3", Keyword.put(opts, :tags, ["b", "c"]))

      assert {:ok, entries} = Memory.recall("agent_1", %{tags: ["a", "b"]}, opts)
      assert length(entries) == 1
      assert hd(entries).key == "k1"
    end

    test "returns empty list when no tags match", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "k1", "v1", Keyword.put(opts, :tags, ["x"]))
      assert {:ok, []} = Memory.recall("agent_1", %{tags: ["z"]}, opts)
    end

    test "scopes tag recall per agent", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "k1", "v1", Keyword.put(opts, :tags, ["shared"]))
      {:ok, _} = Memory.store("agent_2", "k2", "v2", Keyword.put(opts, :tags, ["shared"]))

      assert {:ok, entries} = Memory.recall("agent_1", %{tags: ["shared"]}, opts)
      assert length(entries) == 1
      assert hd(entries).agent_id == "agent_1"
    end
  end

  describe "forget/3 by key" do
    test "deletes an existing entry", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "temp", "data", opts)
      assert {:ok, 1} = Memory.forget("agent_1", %{key: "temp"}, opts)
      assert {:ok, nil} = Memory.recall("agent_1", %{key: "temp"}, opts)
    end

    test "returns 0 when key not found", %{opts: opts} do
      assert {:ok, 0} = Memory.forget("agent_1", %{key: "nope"}, opts)
    end

    test "does not delete across agents", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "keep", "me", opts)
      assert {:ok, 0} = Memory.forget("agent_2", %{key: "keep"}, opts)
      assert {:ok, %Entry{value: "me"}} = Memory.recall("agent_1", %{key: "keep"}, opts)
    end
  end

  describe "forget/3 by tags" do
    test "deletes all entries matching tags", %{opts: opts} do
      {:ok, _} = Memory.store("agent_1", "k1", "v1", Keyword.put(opts, :tags, ["temp"]))
      {:ok, _} = Memory.store("agent_1", "k2", "v2", Keyword.put(opts, :tags, ["temp"]))
      {:ok, _} = Memory.store("agent_1", "k3", "v3", Keyword.put(opts, :tags, ["keep"]))

      assert {:ok, 2} = Memory.forget("agent_1", %{tags: ["temp"]}, opts)
      assert {:ok, nil} = Memory.recall("agent_1", %{key: "k1"}, opts)
      assert {:ok, %Entry{}} = Memory.recall("agent_1", %{key: "k3"}, opts)
    end
  end

  describe "Entry.new/1" do
    test "creates entry with required fields" do
      entry = Entry.new(%{agent_id: "a1", key: "k1"})
      assert entry.agent_id == "a1"
      assert entry.key == "k1"
      assert entry.value == nil
      assert entry.tags == []
      assert entry.metadata == %{}
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn -> Entry.new(%{}) end
    end
  end
end
