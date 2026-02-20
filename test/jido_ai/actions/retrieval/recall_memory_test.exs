defmodule Jido.AI.Actions.Retrieval.RecallMemoryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Retrieval.RecallMemory
  alias Jido.AI.Retrieval.Store

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "requires query and defines top_k default" do
      assert RecallMemory.schema().fields[:query].meta.required == true
      refute RecallMemory.schema().fields[:namespace].meta.required
      assert RecallMemory.schema().fields[:top_k].value == 3
    end
  end

  describe "run/2 happy path" do
    test "recalls top_k memories and returns count" do
      namespace = unique_namespace("recall")

      Store.upsert(namespace, %{id: "m1", text: "Seattle weather has light rain this week", metadata: %{kind: :wx}})

      Store.upsert(namespace, %{id: "m2", text: "Postgres migration runbook for release train", metadata: %{kind: :ops}})

      assert {:ok, %{retrieval: retrieval}} =
               RecallMemory.run(%{namespace: namespace, query: "seattle rain", top_k: 1}, %{})

      assert retrieval.namespace == namespace
      assert retrieval.query == "seattle rain"
      assert retrieval.count == 1
      assert [%{id: "m1", score: score}] = retrieval.memories
      assert is_float(score)
    end

    test "normalizes top_k values lower than 1 to one result" do
      namespace = unique_namespace("topk")

      Store.upsert(namespace, %{id: "m1", text: "memory one"})
      Store.upsert(namespace, %{id: "m2", text: "memory two"})

      assert {:ok, %{retrieval: retrieval}} =
               RecallMemory.run(%{namespace: namespace, query: "memory", top_k: 0}, %{})

      assert retrieval.count == 1
      assert length(retrieval.memories) == 1
    end

    test "resolves namespace from context when params omit namespace" do
      namespace = unique_namespace("ctx_recall")
      Store.upsert(namespace, %{id: "m1", text: "tokenized context memory"})

      context = %{state: %{retrieval: %{namespace: namespace}}, agent: %{id: "agent_fallback"}}

      assert {:ok, %{retrieval: retrieval}} = RecallMemory.run(%{query: "context"}, context)
      assert retrieval.namespace == namespace
      assert retrieval.count == 1
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects missing query" do
      assert {:error, _reason} = Jido.Exec.run(RecallMemory, %{top_k: 2}, %{})
    end

    test "rejects invalid top_k type" do
      assert {:error, _reason} = Jido.Exec.run(RecallMemory, %{query: "hello", top_k: "two"}, %{})
    end
  end

  defp unique_namespace(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
