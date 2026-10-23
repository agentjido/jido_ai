defmodule Jido.AI.DeadlineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Deadline

  test "returns the time that remains" do
    deadline = Deadline.new(1_000)

    assert {:ok, remaining} = Deadline.remaining(deadline)
    assert remaining in 1..1_000
  end

  test "caps an operation timeout at the remaining request time" do
    deadline = Deadline.new(10_000)

    assert {:ok, timeout} = Deadline.cap(deadline, 5_000)
    assert timeout in 1..5_000
  end

  test "returns the configured timeout after the deadline expires" do
    deadline = %Deadline{
      at: System.monotonic_time(:millisecond) - 1,
      timeout: 100
    }

    assert Deadline.remaining(deadline) == {:error, {:request_timeout, 100}}
    assert Deadline.cap(deadline, 50) == {:error, {:request_timeout, 100}}
  end
end
