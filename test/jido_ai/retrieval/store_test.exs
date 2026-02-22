defmodule Jido.AI.Retrieval.StoreTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Retrieval.Store

  @moduletag :unit

  defp unique_namespace(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end

  test "concurrent upsert remains stable under load" do
    namespace = unique_namespace("retrieval_store")

    1..250
    |> Task.async_stream(
      fn i -> Store.upsert(namespace, %{id: "id-#{i}", text: "text-#{i}"}) end,
      max_concurrency: 50,
      timeout: 5_000,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, %{id: id}} when is_binary(id) -> :ok
      other -> flunk("unexpected upsert result: #{inspect(other)}")
    end)

    assert length(Store.namespace_entries(namespace)) == 250
  end

  test "ensure_table! is safe under concurrent calls" do
    1..200
    |> Task.async_stream(
      fn _ -> Store.ensure_table!() end,
      max_concurrency: 50,
      timeout: 5_000,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, :ok} -> :ok
      other -> flunk("unexpected ensure_table result: #{inspect(other)}")
    end)
  end
end
