defmodule Jido.AI.RLM.PartialCollectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.{PartialCollector, Workspace, WorkspaceStore}

  defp setup_workspace do
    {:ok, ref} = WorkspaceStore.init("pc-#{System.unique_integer([:positive])}")
    ref
  end

  defp fetch_partials(ref) do
    case Workspace.fetch(ref, :spawn_partials) do
      {:ok, partials} -> partials
      :error -> %{}
    end
  end

  describe "start_link and emit" do
    test "emits events and writes spawn_partials to workspace" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref)

      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "hello", at_ms: 1000})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert %{"c1" => %{text: "hello", type: :content, done?: false}} = partials
    end
  end

  describe "text truncation" do
    test "truncates text to max_chars_per_chunk keeping tail" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref, max_chars_per_chunk: 10)

      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "abcdefghijklmno", at_ms: 1000})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["c1"].text == "fghijklmno"
      assert byte_size(partials["c1"].text) == 10
    end

    test "accumulates and truncates across multiple emits" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref, max_chars_per_chunk: 8)

      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "abcde", at_ms: 1})
      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "fghij", at_ms: 2})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["c1"].text == "cdefghij"
    end
  end

  describe "multiple chunks" do
    test "tracks chunks independently" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref)

      :ok = PartialCollector.emit(pid, %{chunk_id: "a", type: :content, text: "alpha", at_ms: 1})
      :ok = PartialCollector.emit(pid, %{chunk_id: "b", type: :thinking, text: "beta", at_ms: 2})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["a"].text == "alpha"
      assert partials["a"].type == :content
      assert partials["b"].text == "beta"
      assert partials["b"].type == :thinking
    end
  end

  describe "done type" do
    test "marks chunk as done" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref)

      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "partial", at_ms: 1})
      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :done, text: "", at_ms: 2})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["c1"].done? == true
      assert partials["c1"].text == "partial"
    end
  end

  describe "stop/1" do
    test "flushes final state to workspace" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref)

      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "final", at_ms: 1})
      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["c1"].text == "final"
    end
  end

  describe "rapid emissions" do
    test "handles many rapid emissions without crashing" do
      ref = setup_workspace()
      {:ok, pid} = PartialCollector.start_link(ref)

      for i <- 1..500 do
        :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "x#{i}", at_ms: i})
      end

      :ok = PartialCollector.stop(pid)

      partials = fetch_partials(ref)
      assert partials["c1"].text != ""
      assert partials["c1"].updated_at_ms == 500
    end
  end
end
