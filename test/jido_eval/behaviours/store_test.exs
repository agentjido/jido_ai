defmodule Jido.Eval.StoreTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Store

  defmodule TestStore do
    @behaviour Store

    def init(opts) do
      path = Keyword.get(opts, :path, "test.json")
      {:ok, %{path: path, data: []}}
    end

    def persist(data, state) do
      updated_data = [data | state.data]
      {:ok, %{state | data: updated_data}}
    end

    def finalize(state) do
      send(self(), {:finalized, state.data})
      :ok
    end
  end

  defmodule ErrorStore do
    @behaviour Store

    def init(_opts) do
      {:error, :init_failed}
    end

    def persist(_data, _state) do
      {:error, :persist_failed}
    end

    def finalize(_state) do
      {:error, :finalize_failed}
    end
  end

  describe "behaviour implementation" do
    test "TestStore implements all callbacks correctly" do
      {:ok, state} = TestStore.init(path: "custom.json")
      assert state.path == "custom.json"
      assert state.data == []

      {:ok, new_state} = TestStore.persist(%{id: 1}, state)
      assert new_state.data == [%{id: 1}]

      {:ok, final_state} = TestStore.persist(%{id: 2}, new_state)
      assert final_state.data == [%{id: 2}, %{id: 1}]

      assert TestStore.finalize(final_state) == :ok
      assert_received {:finalized, [%{id: 2}, %{id: 1}]}
    end

    test "TestStore uses default path when not provided" do
      {:ok, state} = TestStore.init([])
      assert state.path == "test.json"
    end

    test "ErrorStore returns errors for all callbacks" do
      assert ErrorStore.init([]) == {:error, :init_failed}
      assert ErrorStore.persist(%{}, nil) == {:error, :persist_failed}
      assert ErrorStore.finalize(nil) == {:error, :finalize_failed}
    end
  end

  describe "behaviour validation" do
    test "behaviour callbacks are defined" do
      callbacks = Store.behaviour_info(:callbacks)

      assert {:init, 1} in callbacks
      assert {:persist, 2} in callbacks
      assert {:finalize, 1} in callbacks
    end

    test "no optional callbacks defined" do
      optional_callbacks = Store.behaviour_info(:optional_callbacks)
      assert optional_callbacks == []
    end
  end
end
