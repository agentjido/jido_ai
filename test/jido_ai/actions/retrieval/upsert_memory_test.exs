defmodule Jido.AI.Actions.Retrieval.UpsertMemoryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Retrieval.UpsertMemory
  alias Jido.AI.Retrieval.Store

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "requires text and provides defaults for optional fields" do
      assert UpsertMemory.schema().fields[:text].meta.required == true
      refute UpsertMemory.schema().fields[:id].meta.required
      refute UpsertMemory.schema().fields[:namespace].meta.required
      assert UpsertMemory.schema().fields[:metadata].value == %{}
    end
  end

  describe "run/2 happy path" do
    test "upserts memory and returns retrieval envelope" do
      namespace = unique_namespace("upsert")

      params = %{
        namespace: namespace,
        id: "m_seattle",
        text: "Seattle forecasts call for light rain this week.",
        metadata: %{source: "weekly_report"}
      }

      assert {:ok, %{retrieval: retrieval}} = UpsertMemory.run(params, %{})
      assert retrieval.namespace == namespace
      assert retrieval.last_upsert.id == "m_seattle"
      assert retrieval.last_upsert.text == "Seattle forecasts call for light rain this week."
      assert retrieval.last_upsert.metadata == %{source: "weekly_report"}
      assert is_integer(retrieval.last_upsert.inserted_at_ms)
      assert is_integer(retrieval.last_upsert.updated_at_ms)

      assert [%{id: "m_seattle"} = entry] = Store.namespace_entries(namespace)
      assert entry.metadata == %{source: "weekly_report"}
    end

    test "resolves namespace from plugin state before state and agent fallbacks" do
      context = %{
        plugin_state: %{retrieval: %{namespace: "ns_plugin"}},
        state: %{retrieval: %{namespace: "ns_state"}},
        agent: %{id: "agent_namespace"}
      }

      assert {:ok, %{retrieval: retrieval}} = UpsertMemory.run(%{text: "cached memory"}, context)
      assert retrieval.namespace == "ns_plugin"
      assert String.starts_with?(retrieval.last_upsert.id, "mem_")
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects missing text" do
      assert {:error, _reason} = Jido.Exec.run(UpsertMemory, %{namespace: unique_namespace("missing_text")}, %{})
    end

    test "rejects invalid metadata type" do
      params = %{
        text: "valid text",
        metadata: "not-a-map",
        namespace: unique_namespace("invalid_metadata")
      }

      assert {:error, _reason} = Jido.Exec.run(UpsertMemory, params, %{})
    end
  end

  defp unique_namespace(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
