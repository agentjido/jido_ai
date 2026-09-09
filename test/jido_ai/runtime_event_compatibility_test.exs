defmodule Jido.AI.RuntimeEventCompatibilityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runtime.Event
  alias Jido.AI.Reasoning.ReAct.Event, as: ReActEvent

  test "exposes the runtime event schema and supported kinds" do
    assert %Zoi.Types.Struct{} = Event.schema()
    assert :input_injected in Event.kinds()
    assert ReActEvent.schema() == Event.schema()
    assert ReActEvent.kinds() == Event.kinds()
  end

  test "validates event fields and kinds through both entry points" do
    attrs = %{
      seq: 0,
      run_id: "run",
      request_id: "request",
      iteration: 0,
      kind: :request_started
    }

    assert %Event{kind: :request_started, data: %{}} = Event.new(attrs)
    assert %Event{kind: :request_started} = ReActEvent.new(attrs)

    assert_raise ArgumentError, ~r/invalid runtime event/, fn -> Event.new(%{}) end

    assert_raise ArgumentError, ~r/invalid runtime event kind/, fn ->
      Event.new(%{attrs | kind: :unknown})
    end
  end
end
