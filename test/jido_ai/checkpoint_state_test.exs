defmodule Jido.AI.CheckpointStateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Checkpoint

  defmodule ExampleTool do
    use Jido.Action,
      name: "checkpoint_example_tool",
      description: "A tool used to test checkpoint state",
      schema: Zoi.object(%{})

    def run(params, _context), do: {:ok, params}
  end

  test "passes non-map state through unchanged" do
    assert Checkpoint.sanitize_state(:state) == :state
    assert Checkpoint.rehydrate_state([:state]) == [:state]
  end

  test "removes a stream sink and interrupts an active request" do
    state = %{
      requests: %{
        "request-1" => %{status: :pending, stream_to: {:pid, self()}, query: "hello"}
      }
    }

    request = Checkpoint.sanitize_state(state).requests["request-1"]

    assert request.status == :failed
    assert request.error == :stream_interrupted
    assert request.stream_interrupted == true
    refute Map.has_key?(request, :stream_to)
  end

  test "resets an active ReAct strategy and its process handles" do
    state = %{
      __strategy__: %{
        status: :awaiting_llm,
        active_request_id: "request-1",
        react_worker_pid: self(),
        react_worker_status: :running,
        pending_input_server: self(),
        iteration: 4,
        final_answer: "partial"
      }
    }

    strategy = Checkpoint.sanitize_state(state).__strategy__

    assert strategy.status == :idle
    assert strategy.active_request_id == nil
    assert strategy.react_worker_pid == nil
    assert strategy.react_worker_status == :missing
    assert strategy.pending_input_server == nil
    assert strategy.iteration == 0
    assert strategy.final_answer == nil
  end

  test "resets ReAct handles without changing an idle strategy result" do
    state = %{
      __strategy__: %{
        status: :idle,
        result: "complete",
        react_worker_pid: self(),
        react_worker_status: :missing
      }
    }

    strategy = Checkpoint.rehydrate_state(state).__strategy__

    assert strategy.status == :idle
    assert strategy.result == "complete"
    assert strategy.react_worker_pid == nil
    assert strategy.react_worker_status == :missing
  end

  test "rebuilds ReqLLM tools from the checkpointed action list" do
    state = %{
      __strategy__: %{
        config: %{tools: [ExampleTool], reqllm_tools: [:stale]}
      }
    }

    strategy = Checkpoint.sanitize_state(state).__strategy__

    assert [%ReqLLM.Tool{name: "checkpoint_example_tool"}] = strategy.config.reqllm_tools
  end

  test "leaves state without a strategy unchanged" do
    state = %{value: 1}
    assert Checkpoint.sanitize_state(state) == state
  end
end
