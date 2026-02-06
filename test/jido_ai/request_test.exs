defmodule JidoTest.AI.RequestTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Request.Handle

  describe "Handle struct" do
    test "new/3 creates a pending request with timestamp" do
      handle = Handle.new("req-123", self(), "What is 2+2?")

      assert handle.id == "req-123"
      assert handle.server == self()
      assert handle.query == "What is 2+2?"
      assert handle.status == :pending
      assert handle.result == nil
      assert handle.error == nil
      assert is_integer(handle.inserted_at)
      assert handle.completed_at == nil
    end

    test "complete/2 marks request as completed with result" do
      handle = Handle.new("req-123", self(), "query")
      completed = Handle.complete(handle, "answer")

      assert completed.status == :completed
      assert completed.result == "answer"
      assert is_integer(completed.completed_at)
      assert completed.completed_at >= handle.inserted_at
    end

    test "fail/2 marks request as failed with error" do
      handle = Handle.new("req-123", self(), "query")
      failed = Handle.fail(handle, :timeout)

      assert failed.status == :failed
      assert failed.error == :timeout
      assert is_integer(failed.completed_at)
    end
  end

  describe "ensure_request_id/1" do
    test "returns existing request_id when present" do
      params = %{query: "test", request_id: "existing-id"}
      {id, new_params} = Request.ensure_request_id(params)

      assert id == "existing-id"
      assert new_params == params
    end

    test "generates new request_id when not present" do
      params = %{query: "test"}
      {id, new_params} = Request.ensure_request_id(params)

      assert is_binary(id)
      assert String.length(id) > 0
      assert new_params.request_id == id
      assert new_params.query == "test"
    end
  end

  describe "state management" do
    defmodule MockAgent do
      defstruct [:state]
    end

    test "init_state/2 adds request tracking fields" do
      state = Request.init_state(%{existing: "field"})

      assert state.existing == "field"
      assert state.requests == %{}
      assert state.__request_tracking__.max_requests == 100
    end

    test "init_state/2 respects max_requests option" do
      state = Request.init_state(%{}, max_requests: 50)

      assert state.__request_tracking__.max_requests == 50
    end

    test "start_request/3 adds request to state" do
      agent = %MockAgent{state: Request.init_state(%{})}
      agent = Request.start_request(agent, "req-1", "What is 2+2?")

      assert Map.has_key?(agent.state.requests, "req-1")
      request = agent.state.requests["req-1"]
      assert request.query == "What is 2+2?"
      assert request.status == :pending
      assert is_integer(request.inserted_at)

      # Check backward compat fields
      assert agent.state.last_query == "What is 2+2?"
      assert agent.state.last_request_id == "req-1"
      assert agent.state.completed == false
      assert agent.state.last_answer == ""
    end

    test "complete_request/3 updates request with result" do
      agent = %MockAgent{state: Request.init_state(%{})}
      agent = Request.start_request(agent, "req-1", "query")
      agent = Request.complete_request(agent, "req-1", "The answer is 4")

      request = agent.state.requests["req-1"]
      assert request.status == :completed
      assert request.result == "The answer is 4"
      assert is_integer(request.completed_at)

      # Check backward compat fields
      assert agent.state.last_answer == "The answer is 4"
      assert agent.state.completed == true
    end

    test "fail_request/3 updates request with error" do
      agent = %MockAgent{state: Request.init_state(%{})}
      agent = Request.start_request(agent, "req-1", "query")
      agent = Request.fail_request(agent, "req-1", :llm_error)

      request = agent.state.requests["req-1"]
      assert request.status == :failed
      assert request.error == :llm_error
      assert agent.state.completed == true
    end

    test "get_request/2 retrieves request by id" do
      agent = %MockAgent{state: Request.init_state(%{})}
      agent = Request.start_request(agent, "req-1", "query")

      assert Request.get_request(agent, "req-1").query == "query"
      assert Request.get_request(agent, "nonexistent") == nil
    end

    test "get_result/2 returns appropriate tuple based on status" do
      agent = %MockAgent{state: Request.init_state(%{})}

      # Pending
      agent = Request.start_request(agent, "req-1", "query")
      assert {:pending, _} = Request.get_result(agent, "req-1")

      # Completed
      agent = Request.complete_request(agent, "req-1", "answer")
      assert {:ok, "answer"} = Request.get_result(agent, "req-1")

      # Failed
      agent = Request.start_request(agent, "req-2", "query2")
      agent = Request.fail_request(agent, "req-2", :error)
      assert {:error, :error} = Request.get_result(agent, "req-2")

      # Not found
      assert Request.get_result(agent, "nonexistent") == nil
    end

    test "evicts old requests when max_requests exceeded" do
      agent = %MockAgent{state: Request.init_state(%{}, max_requests: 3)}

      # Add 5 requests
      agent = Request.start_request(agent, "req-1", "q1")
      Process.sleep(1)
      agent = Request.start_request(agent, "req-2", "q2")
      Process.sleep(1)
      agent = Request.start_request(agent, "req-3", "q3")
      Process.sleep(1)
      agent = Request.start_request(agent, "req-4", "q4")
      Process.sleep(1)
      agent = Request.start_request(agent, "req-5", "q5")

      # Should only have 3 most recent
      assert map_size(agent.state.requests) == 3
      # Most recent should be kept
      assert Map.has_key?(agent.state.requests, "req-5")
      assert Map.has_key?(agent.state.requests, "req-4")
      assert Map.has_key?(agent.state.requests, "req-3")
      # Oldest should be evicted
      refute Map.has_key?(agent.state.requests, "req-1")
      refute Map.has_key?(agent.state.requests, "req-2")
    end
  end

  describe "concurrent request isolation" do
    test "multiple requests maintain separate state" do
      agent = %{state: Request.init_state(%{})}

      # Start two concurrent requests
      agent = Request.start_request(agent, "req-a", "Query A")
      agent = Request.start_request(agent, "req-b", "Query B")

      # Both should exist independently
      assert agent.state.requests["req-a"].query == "Query A"
      assert agent.state.requests["req-b"].query == "Query B"
      assert agent.state.requests["req-a"].status == :pending
      assert agent.state.requests["req-b"].status == :pending

      # Complete A
      agent = Request.complete_request(agent, "req-a", "Answer A")

      # A is completed, B still pending
      assert agent.state.requests["req-a"].status == :completed
      assert agent.state.requests["req-a"].result == "Answer A"
      assert agent.state.requests["req-b"].status == :pending

      # Complete B
      agent = Request.complete_request(agent, "req-b", "Answer B")

      # Both completed with correct results
      assert agent.state.requests["req-a"].result == "Answer A"
      assert agent.state.requests["req-b"].result == "Answer B"
    end
  end
end
