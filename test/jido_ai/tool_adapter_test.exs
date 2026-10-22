defmodule Jido.AI.ToolAdapterTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ToolAdapter

  defmodule Add do
    use Jido.Action,
      name: "add",
      description: "Add two integers",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    @impl true
    def run(%{left: left, right: right}, context) do
      {:ok, %{sum: left + right, request_id: context.request_id}}
    end
  end

  defmodule Slow do
    use Jido.Action,
      name: "slow",
      description: "Run longer than the remaining request time",
      schema: Zoi.object(%{})

    @impl true
    def run(_params, _context) do
      Process.sleep(500)
      {:ok, %{finished: true}}
    end
  end

  test "a ReqLLM tool runs its Jido Action through Jido Exec" do
    assert {:ok, tool} = ToolAdapter.from_executable(Add, %{request_id: "request-1"})
    assert tool.name == "add"

    assert ReqLLM.Tool.execute(tool, %{"left" => 2, "right" => 3}) ==
             {:ok, %{sum: 5, request_id: "request-1"}}
  end

  test "duplicate tool names return an explicit error" do
    assert ToolAdapter.from_executables([Add, Add]) ==
             {:error, {:duplicate_tool_name, "add"}}
  end

  test "a ReqLLM tool cannot start after the total request deadline" do
    spec = %{
      kind: :action,
      target: Add,
      name: "add",
      description: "Add two integers",
      timeout: 5_000
    }

    deadline = %{at: System.monotonic_time(:millisecond) - 1, timeout: 100}

    assert {:ok, [tool]} = ToolAdapter.from_specs([spec], %{}, deadline: deadline)

    assert ReqLLM.Tool.execute(tool, %{"left" => 2, "right" => 3}) ==
             {:error, {:request_timeout, 100}}
  end

  @tag capture_log: true
  test "a ReqLLM tool uses the remaining total request time" do
    spec = %{
      kind: :action,
      target: Slow,
      name: "slow",
      description: "Run longer than the remaining request time",
      timeout: 5_000
    }

    deadline = %{at: System.monotonic_time(:millisecond) + 250, timeout: 250}

    assert {:ok, [tool]} = ToolAdapter.from_specs([spec], %{}, deadline: deadline)

    assert {:error, %Jido.Action.Error.TimeoutError{timeout: timeout}} =
             ReqLLM.Tool.execute(tool, %{})

    assert timeout in 1..250
  end
end
