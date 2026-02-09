defmodule Jido.AI.RLM.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.Workspace

  describe "init/destroy lifecycle" do
    test "creates and destroys a workspace" do
      {:ok, ref} = Workspace.init("req-1")
      assert is_pid(ref.pid)
      assert is_reference(ref.table)
      assert ref.adapter == Jido.AI.RLM.Workspace.ETSAdapter
      assert :ok == Workspace.destroy(ref)
    end

    test "destroy deletes the ETS table" do
      {:ok, ref} = Workspace.init("req-2")
      Workspace.put(ref, :key, "value")
      assert {:ok, "value"} == Workspace.fetch(ref, :key)
      :ok = Workspace.destroy(ref)
      assert_raise ArgumentError, fn -> Workspace.fetch(ref, :key) end
    end
  end

  describe "put/fetch" do
    test "stores and retrieves values" do
      {:ok, ref} = Workspace.init("req-3")
      :ok = Workspace.put(ref, :name, "test")
      assert {:ok, "test"} == Workspace.fetch(ref, :name)
      Workspace.destroy(ref)
    end

    test "fetch returns :error for missing keys" do
      {:ok, ref} = Workspace.init("req-4")
      assert :error == Workspace.fetch(ref, :missing)
      Workspace.destroy(ref)
    end

    test "put overwrites existing values" do
      {:ok, ref} = Workspace.init("req-5")
      :ok = Workspace.put(ref, :counter, 1)
      :ok = Workspace.put(ref, :counter, 2)
      assert {:ok, 2} == Workspace.fetch(ref, :counter)
      Workspace.destroy(ref)
    end
  end

  describe "delete_key" do
    test "removes a key" do
      {:ok, ref} = Workspace.init("req-6")
      :ok = Workspace.put(ref, :temp, "data")
      :ok = Workspace.delete_key(ref, :temp)
      assert :error == Workspace.fetch(ref, :temp)
      Workspace.destroy(ref)
    end
  end

  describe "update" do
    test "updates with default when key missing" do
      {:ok, ref} = Workspace.init("req-7")
      :ok = Workspace.update(ref, :counter, 0, &(&1 + 1))
      assert {:ok, 1} == Workspace.fetch(ref, :counter)
      Workspace.destroy(ref)
    end

    test "updates existing value" do
      {:ok, ref} = Workspace.init("req-8")
      :ok = Workspace.put(ref, :items, [])
      :ok = Workspace.update(ref, :items, [], &["a" | &1])
      :ok = Workspace.update(ref, :items, [], &["b" | &1])
      assert {:ok, ["b", "a"]} == Workspace.fetch(ref, :items)
      Workspace.destroy(ref)
    end

    test "atomic update under concurrent access" do
      {:ok, ref} = Workspace.init("req-9")
      :ok = Workspace.put(ref, :counter, 0)

      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            Workspace.update(ref, :counter, 0, &(&1 + 1))
          end)
        end

      Enum.each(tasks, &Task.await/1)
      assert {:ok, 100} == Workspace.fetch(ref, :counter)
      Workspace.destroy(ref)
    end
  end

  describe "multiple keys" do
    test "stores multiple independent keys" do
      {:ok, ref} = Workspace.init("req-10")
      :ok = Workspace.put(ref, :context, "large binary")
      :ok = Workspace.put(ref, :workspace, %{chunks: []})
      assert {:ok, "large binary"} == Workspace.fetch(ref, :context)
      assert {:ok, %{chunks: []}} == Workspace.fetch(ref, :workspace)
      Workspace.destroy(ref)
    end
  end
end
