defmodule Jido.AI.Actions.Retrieval.ClearMemoryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Retrieval.ClearMemory
  alias Jido.AI.Retrieval.Store

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "accepts optional namespace" do
      refute ClearMemory.schema().fields[:namespace].meta.required
    end
  end

  describe "run/2 happy path" do
    test "clears memories in explicit namespace and reports cleared count" do
      namespace = unique_namespace("clear")

      Store.upsert(namespace, %{id: "m1", text: "first"})
      Store.upsert(namespace, %{id: "m2", text: "second"})

      assert {:ok, %{retrieval: retrieval}} = ClearMemory.run(%{namespace: namespace}, %{})
      assert retrieval.namespace == namespace
      assert retrieval.cleared == 2
      assert Store.namespace_entries(namespace) == []
    end

    test "resolves namespace from context when params omit namespace" do
      namespace = unique_namespace("ctx_clear")
      Store.upsert(namespace, %{id: "m1", text: "memory to clear"})

      context = %{agent: %{id: namespace}}

      assert {:ok, %{retrieval: retrieval}} = ClearMemory.run(%{}, context)
      assert retrieval.namespace == namespace
      assert retrieval.cleared == 1
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects invalid namespace type" do
      assert {:error, _reason} = Jido.Exec.run(ClearMemory, %{namespace: 123}, %{})
    end
  end

  defp unique_namespace(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
