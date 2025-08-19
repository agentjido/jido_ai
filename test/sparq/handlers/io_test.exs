defmodule Sparq.Handlers.IOTest do
  use ExUnit.Case, async: true
  alias Sparq.Handlers.IO
  alias Sparq.Context
  alias Sparq.Debug.Event

  test "handle/4 handles print operation" do
    msg = "Hello, World!"
    ctx = Context.new()
    {result, new_ctx} = IO.handle(:print, %{}, [msg], ctx)
    assert result == msg
    assert {:value, %Event{type: :frame_entry, data: ^msg}} = :queue.peek_r(new_ctx.event_history)
  end

  test "validate/2 validates print with correct arity" do
    assert :ok = IO.validate(:print, ["test message"])
  end

  test "validate/2 validates print with incorrect arity" do
    assert {:error, :invalid_arity} = IO.validate(:print, [])
    assert {:error, :invalid_arity} = IO.validate(:print, ["msg1", "msg2"])
  end
end
