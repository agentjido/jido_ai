defmodule Jido.AI.RLM.ReaperTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.Reaper
  alias Jido.AI.RLM.WorkspaceStore

  defp start_reaper(_ctx) do
    name = :"reaper_#{System.unique_integer([:positive])}"
    {:ok, pid} = Reaper.start_link(name: name)
    %{reaper: pid, name: name}
  end

  describe "workspace tracking" do
    setup [:start_reaper]

    test "reaps workspace after TTL expires", %{name: name} do
      {:ok, ref} = WorkspaceStore.init("reap-ws-1")
      :ok = Reaper.track(name, {:workspace, ref}, 50)

      assert WorkspaceStore.get(ref) == %{}
      Process.sleep(100)
      assert_raise ArgumentError, fn -> WorkspaceStore.get(ref) end
    end
  end

  describe "context tracking (ets backend)" do
    setup [:start_reaper]

    test "reaps ets context after TTL expires", %{name: name} do
      {:ok, ref} = ContextStore.put("reap-data", "reap-ctx-1", inline_threshold: 1)
      assert ref.backend == :ets
      :ok = Reaper.track(name, {:context, ref}, 50)

      assert {:ok, "reap-data"} == ContextStore.fetch(ref)
      Process.sleep(100)
      assert {:error, :not_found} == ContextStore.fetch(ref)
    end
  end

  describe "untrack" do
    setup [:start_reaper]

    test "untracking prevents cleanup", %{name: name} do
      {:ok, ref} = WorkspaceStore.init("reap-ws-2")
      :ok = Reaper.track(name, {:workspace, ref}, 50)
      :ok = Reaper.untrack(name, {:workspace, ref})

      Process.sleep(100)
      assert WorkspaceStore.get(ref) == %{}
      WorkspaceStore.delete(ref)
    end
  end

  describe "re-tracking" do
    setup [:start_reaper]

    test "re-tracking resets the timer", %{name: name} do
      {:ok, ref} = WorkspaceStore.init("reap-ws-3")
      :ok = Reaper.track(name, {:workspace, ref}, 50)

      Process.sleep(30)
      :ok = Reaper.track(name, {:workspace, ref}, 100)

      Process.sleep(50)
      assert WorkspaceStore.get(ref) == %{}

      Process.sleep(80)
      assert_raise ArgumentError, fn -> WorkspaceStore.get(ref) end
    end
  end

  describe "already-deleted resources" do
    setup [:start_reaper]

    test "reaping an already-deleted workspace does not crash", %{name: name} do
      {:ok, ref} = WorkspaceStore.init("reap-ws-4")
      :ok = Reaper.track(name, {:workspace, ref}, 50)
      :ok = WorkspaceStore.delete(ref)

      Process.sleep(100)
      assert Process.alive?(name |> Process.whereis())
    end

    test "reaping an already-deleted ets context does not crash", %{name: name} do
      {:ok, ref} = ContextStore.put("gone", "reap-ctx-2", inline_threshold: 1)
      :ok = Reaper.track(name, {:context, ref}, 50)
      :ok = ContextStore.delete(ref)

      Process.sleep(100)
      assert Process.alive?(name |> Process.whereis())
    end
  end

  describe "inline context" do
    setup [:start_reaper]

    test "tracking inline context is safe (no-op delete)", %{name: name} do
      {:ok, ref} = ContextStore.put("small", "reap-ctx-3")
      assert ref.backend == :inline
      :ok = Reaper.track(name, {:context, ref}, 50)

      Process.sleep(100)
      assert Process.alive?(name |> Process.whereis())
    end
  end
end
