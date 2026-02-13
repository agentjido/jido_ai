defmodule JidoAITest.Actions.OrchestrationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive

  alias Jido.AI.Actions.Orchestration.{
    AggregateResults,
    DiscoverCapabilities,
    SpawnChildAgent,
    StopChildAgent
  }

  describe "SpawnChildAgent" do
    test "creates SpawnAgent directive with required params" do
      params = %{
        agent: FakeWorkerAgent,
        tag: :worker_1
      }

      assert {:ok, result} = SpawnChildAgent.run(params, %{})
      assert %Directive.SpawnAgent{} = result.directive
      assert result.directive.agent == FakeWorkerAgent
      assert result.directive.tag == :worker_1
      assert result.tag == :worker_1
    end

    test "includes opts and meta when provided" do
      params = %{
        agent: FakeWorkerAgent,
        tag: :processor,
        opts: %{id: "custom-id"},
        meta: %{task_type: "analysis"}
      }

      assert {:ok, result} = SpawnChildAgent.run(params, %{})
      assert result.directive.opts == %{id: "custom-id"}
      assert result.directive.meta == %{task_type: "analysis"}
    end
  end

  describe "StopChildAgent" do
    test "creates StopChild directive with tag" do
      params = %{tag: :worker_1}

      assert {:ok, result} = StopChildAgent.run(params, %{})
      assert %Directive.StopChild{} = result.directive
      assert result.directive.tag == :worker_1
      assert result.directive.reason == :normal
    end

    test "includes custom reason when provided" do
      params = %{tag: :processor, reason: :shutdown}

      assert {:ok, result} = StopChildAgent.run(params, %{})
      assert result.directive.reason == :shutdown
    end
  end

  describe "DiscoverCapabilities" do
    defmodule FakeAgent do
      def __agent_config__, do: [description: "Test agent"]
      def actions, do: [{"test_action", FakeAction}]
      def skills, do: [{FakeSkill, []}]
      def capabilities, do: ["testing", "demo"]
    end

    test "extracts capabilities from agent modules" do
      params = %{agent_modules: [FakeAgent]}

      assert {:ok, result} = DiscoverCapabilities.run(params, %{})
      assert [capability] = result.capabilities
      assert capability.module == FakeAgent
      assert capability.name == "fake_agent"
      assert capability.description == "Test agent"
      assert capability.capabilities == ["testing", "demo"]
    end

    test "handles modules that don't exist" do
      params = %{agent_modules: [NonExistentModule]}

      assert {:ok, result} = DiscoverCapabilities.run(params, %{})
      assert result.capabilities == []
    end
  end

  describe "AggregateResults" do
    test "merges results with :merge strategy" do
      params = %{
        results: [
          %{source: :worker_1, data: %{count: 10}},
          %{source: :worker_2, data: %{sum: 100}}
        ],
        strategy: :merge
      }

      assert {:ok, result} = AggregateResults.run(params, %{})
      assert result.strategy == :merge
      assert result.sources == [:worker_1, :worker_2]
      assert result.aggregated.data.count == 10
      assert result.aggregated.data.sum == 100
    end

    test "selects best result with :best strategy" do
      params = %{
        results: [
          %{source: :worker_1, score: 0.8, answer: "A"},
          %{source: :worker_2, score: 0.95, answer: "B"},
          %{source: :worker_3, score: 0.7, answer: "C"}
        ],
        strategy: :best
      }

      assert {:ok, result} = AggregateResults.run(params, %{})
      assert result.strategy == :best
      assert result.aggregated.answer == "B"
      assert result.aggregated.score == 0.95
    end

    test "performs majority vote with :vote strategy" do
      params = %{
        results: [
          %{source: :worker_1, decision: :approve},
          %{source: :worker_2, decision: :approve},
          %{source: :worker_3, decision: :reject}
        ],
        strategy: :vote
      }

      assert {:ok, result} = AggregateResults.run(params, %{})
      assert result.strategy == :vote
      assert result.aggregated.decision == :approve
      assert result.aggregated.votes == %{approve: 2, reject: 1}
    end
  end
end
