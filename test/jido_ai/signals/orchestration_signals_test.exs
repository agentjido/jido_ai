defmodule JidoAITest.Signals.OrchestrationSignalsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Signal.{
    DelegationRequest,
    DelegationResult,
    DelegationError,
    CapabilityQuery,
    CapabilityResponse
  }

  alias Jido.AI.Plugins.Orchestration

  describe "DelegationRequest" do
    test "creates valid delegation request signal" do
      assert {:ok, signal} =
               DelegationRequest.new(%{
                 call_id: "call_123",
                 task: "Analyze this document",
                 target: :doc_analyzer
               })

      assert signal.type == "ai.delegation.request"
      assert signal.data.call_id == "call_123"
      assert signal.data.task == "Analyze this document"
      assert signal.data.target == :doc_analyzer
      assert signal.data.constraints == %{}
    end

    test "includes constraints when provided" do
      assert {:ok, signal} =
               DelegationRequest.new(%{
                 call_id: "call_456",
                 task: "Process data",
                 target: :processor,
                 constraints: %{timeout_ms: 5000, max_cost: 0.10}
               })

      assert signal.data.constraints == %{timeout_ms: 5000, max_cost: 0.10}
    end
  end

  describe "DelegationResult" do
    test "creates valid delegation result signal" do
      assert {:ok, signal} =
               DelegationResult.new(%{
                 call_id: "call_123",
                 result: {:ok, %{answer: "Analysis complete"}},
                 source_agent: :doc_analyzer
               })

      assert signal.type == "ai.delegation.result"
      assert signal.data.call_id == "call_123"
      assert signal.data.result == {:ok, %{answer: "Analysis complete"}}
      assert signal.data.source_agent == :doc_analyzer
    end

    test "includes duration when provided" do
      assert {:ok, signal} =
               DelegationResult.new(%{
                 call_id: "call_123",
                 result: {:ok, %{}},
                 source_agent: :worker,
                 duration_ms: 1500
               })

      assert signal.data.duration_ms == 1500
    end
  end

  describe "DelegationError" do
    test "creates valid delegation error signal" do
      assert {:ok, signal} =
               DelegationError.new(%{
                 call_id: "call_123",
                 error_type: :timeout,
                 message: "Task timed out after 5000ms"
               })

      assert signal.type == "ai.delegation.error"
      assert signal.data.error_type == :timeout
      assert signal.data.message == "Task timed out after 5000ms"
    end

    test "includes source agent when provided" do
      assert {:ok, signal} =
               DelegationError.new(%{
                 call_id: "call_123",
                 error_type: :crash,
                 message: "Child crashed",
                 source_agent: :worker_1
               })

      assert signal.data.source_agent == :worker_1
    end
  end

  describe "CapabilityQuery" do
    test "creates valid capability query signal" do
      assert {:ok, signal} =
               CapabilityQuery.new(%{
                 call_id: "query_123"
               })

      assert signal.type == "ai.capability.query"
      assert signal.data.call_id == "query_123"
      assert signal.data.required_capabilities == []
    end

    test "includes required capabilities filter" do
      assert {:ok, signal} =
               CapabilityQuery.new(%{
                 call_id: "query_456",
                 required_capabilities: ["pdf_parsing", "summarization"]
               })

      assert signal.data.required_capabilities == ["pdf_parsing", "summarization"]
    end
  end

  describe "CapabilityResponse" do
    test "creates valid capability response signal" do
      assert {:ok, signal} =
               CapabilityResponse.new(%{
                 call_id: "query_123",
                 agent_ref: :doc_analyzer,
                 capabilities: %{
                   name: "doc_analyzer",
                   capabilities: ["pdf", "summarization"],
                   description: "Document analysis agent"
                 }
               })

      assert signal.type == "ai.capability.response"
      assert signal.data.agent_ref == :doc_analyzer
      assert signal.data.capabilities.name == "doc_analyzer"
    end
  end

  describe "Orchestration skill helpers" do
    test "delegation_request creates signal" do
      signal = Orchestration.delegation_request("call_1", "task", :target)
      assert signal.type == "ai.delegation.request"
      assert signal.data.call_id == "call_1"
    end

    test "delegation_result creates signal" do
      signal = Orchestration.delegation_result("call_1", {:ok, %{}}, :worker)
      assert signal.type == "ai.delegation.result"
    end

    test "delegation_error creates signal" do
      signal = Orchestration.delegation_error("call_1", :timeout, "Timed out")
      assert signal.type == "ai.delegation.error"
    end

    test "generate_call_id creates unique IDs" do
      id1 = Orchestration.generate_call_id()
      id2 = Orchestration.generate_call_id()
      assert String.starts_with?(id1, "delegation_")
      assert id1 != id2
    end
  end
end
