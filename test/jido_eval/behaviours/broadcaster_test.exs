defmodule Jido.Eval.BroadcasterTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Broadcaster

  defmodule TestBroadcaster do
    @behaviour Broadcaster

    def publish(event, data, opts) do
      send(self(), {:published, event, data, opts})
      :ok
    end
  end

  defmodule ErrorBroadcaster do
    @behaviour Broadcaster

    def publish(_event, _data, _opts) do
      {:error, :publish_failed}
    end
  end

  describe "behaviour implementation" do
    test "TestBroadcaster implements publish callback" do
      event = :evaluation_started
      data = %{run_id: "test-123"}
      opts = [prefix: [:test]]

      assert TestBroadcaster.publish(event, data, opts) == :ok
      assert_received {:published, :evaluation_started, %{run_id: "test-123"}, [prefix: [:test]]}
    end

    test "ErrorBroadcaster returns error" do
      assert ErrorBroadcaster.publish(:test, %{}, []) == {:error, :publish_failed}
    end
  end

  describe "behaviour validation" do
    test "behaviour callbacks are defined" do
      callbacks = Broadcaster.behaviour_info(:callbacks)

      assert {:publish, 3} in callbacks
    end

    test "no optional callbacks defined" do
      optional_callbacks = Broadcaster.behaviour_info(:optional_callbacks)
      assert optional_callbacks == []
    end
  end
end
