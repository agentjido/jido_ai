defmodule JidoTest.AI.RequestTrackingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RequestTracking
  alias Jido.AI.RequestTracking.Request

  describe "Request struct" do
    test "new/3 creates a pending request with timestamp" do
      request = Request.new("req-123", self(), "What is 2+2?")

      assert request.id == "req-123"
      assert request.server == self()
      assert request.query == "What is 2+2?"
      assert request.status == :pending
      assert request.result == nil
      assert request.error == nil
      assert is_integer(request.inserted_at)
      assert request.completed_at == nil
    end

    test "complete/2 marks request as completed with result" do
      request = Request.new("req-123", self(), "query")
      completed = Request.complete(request, "answer")

      assert completed.status == :completed
      assert completed.result == "answer"
      assert is_integer(completed.completed_at)
      assert completed.completed_at >= request.inserted_at
    end

    test "fail/2 marks request as failed with error" do
      request = Request.new("req-123", self(), "query")
      failed = Request.fail(request, :timeout)

      assert failed.status == :failed
      assert failed.error == :timeout
      assert is_integer(failed.completed_at)
    end
  end

  describe "ensure_request_id/1" do
    test "returns existing request_id when present" do
      params = %{query: "test", request_id: "existing-id"}
      {id, new_params} = RequestTracking.ensure_request_id(params)

      assert id == "existing-id"
      assert new_params == params
    end

    test "generates new request_id when not present" do
      params = %{query: "test"}
      {id, new_params} = RequestTracking.ensure_request_id(params)

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
      state = RequestTracking.init_state(%{existing: "field"})

      assert state.existing == "field"
      assert state.requests == %{}
      assert state.__request_tracking__.max_requests == 100
    end

    test "init_state/2 respects max_requests option" do
      state = RequestTracking.init_state(%{}, max_requests: 50)

      assert state.__request_tracking__.max_requests == 50
    end

    test "start_request/3 adds request to state" do
      agent = %MockAgent{state: RequestTracking.init_state(%{})}
      agent = RequestTracking.start_request(agent, "req-1", "What is 2+2?")

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
      agent = %MockAgent{state: RequestTracking.init_state(%{})}
      agent = RequestTracking.start_request(agent, "req-1", "query")
      agent = RequestTracking.complete_request(agent, "req-1", "The answer is 4")

      request = agent.state.requests["req-1"]
      assert request.status == :completed
      assert request.result == "The answer is 4"
      assert is_integer(request.completed_at)

      # Check backward compat fields
      assert agent.state.last_answer == "The answer is 4"
      assert agent.state.completed == true
    end

    test "fail_request/3 updates request with error" do
      agent = %MockAgent{state: RequestTracking.init_state(%{})}
      agent = RequestTracking.start_request(agent, "req-1", "query")
      agent = RequestTracking.fail_request(agent, "req-1", :llm_error)

      request = agent.state.requests["req-1"]
      assert request.status == :failed
      assert request.error == :llm_error
      assert agent.state.completed == true
    end

    test "get_request/2 retrieves request by id" do
      agent = %MockAgent{state: RequestTracking.init_state(%{})}
      agent = RequestTracking.start_request(agent, "req-1", "query")

      assert RequestTracking.get_request(agent, "req-1").query == "query"
      assert RequestTracking.get_request(agent, "nonexistent") == nil
    end

    test "get_result/2 returns appropriate tuple based on status" do
      agent = %MockAgent{state: RequestTracking.init_state(%{})}

      # Pending
      agent = RequestTracking.start_request(agent, "req-1", "query")
      assert {:pending, _} = RequestTracking.get_result(agent, "req-1")

      # Completed
      agent = RequestTracking.complete_request(agent, "req-1", "answer")
      assert {:ok, "answer"} = RequestTracking.get_result(agent, "req-1")

      # Failed
      agent = RequestTracking.start_request(agent, "req-2", "query2")
      agent = RequestTracking.fail_request(agent, "req-2", :error)
      assert {:error, :error} = RequestTracking.get_result(agent, "req-2")

      # Not found
      assert RequestTracking.get_result(agent, "nonexistent") == nil
    end

    test "evicts old requests when max_requests exceeded" do
      agent = %MockAgent{state: RequestTracking.init_state(%{}, max_requests: 3)}

      # Add 5 requests
      agent = RequestTracking.start_request(agent, "req-1", "q1")
      Process.sleep(1)
      agent = RequestTracking.start_request(agent, "req-2", "q2")
      Process.sleep(1)
      agent = RequestTracking.start_request(agent, "req-3", "q3")
      Process.sleep(1)
      agent = RequestTracking.start_request(agent, "req-4", "q4")
      Process.sleep(1)
      agent = RequestTracking.start_request(agent, "req-5", "q5")

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
      agent = %{state: RequestTracking.init_state(%{})}

      # Start two concurrent requests
      agent = RequestTracking.start_request(agent, "req-a", "Query A")
      agent = RequestTracking.start_request(agent, "req-b", "Query B")

      # Both should exist independently
      assert agent.state.requests["req-a"].query == "Query A"
      assert agent.state.requests["req-b"].query == "Query B"
      assert agent.state.requests["req-a"].status == :pending
      assert agent.state.requests["req-b"].status == :pending

      # Complete A
      agent = RequestTracking.complete_request(agent, "req-a", "Answer A")

      # A is completed, B still pending
      assert agent.state.requests["req-a"].status == :completed
      assert agent.state.requests["req-a"].result == "Answer A"
      assert agent.state.requests["req-b"].status == :pending

      # Complete B
      agent = RequestTracking.complete_request(agent, "req-b", "Answer B")

      # Both completed with correct results
      assert agent.state.requests["req-a"].result == "Answer A"
      assert agent.state.requests["req-b"].result == "Answer B"
    end
  end
end
