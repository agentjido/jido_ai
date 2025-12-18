defmodule Jido.AI.Runner.GEPA.FeedbackAggregationTest do
  @moduledoc """
  Basic integration tests for GEPA Task 1.3.4: Feedback Aggregation.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.{FeedbackAggregation, FeedbackAggregator, Reflector}

  describe "FeedbackAggregator basic integration" do
    test "requires reflections parameter" do
      assert {:error, :missing_reflections} = FeedbackAggregator.aggregate_feedback([])
    end

    test "errors on empty reflections list" do
      assert {:error, :empty_reflections} = FeedbackAggregator.aggregate_feedback(reflections: [])
    end

    test "aggregates feedback from single reflection" do
      reflection = %Reflector.ParsedReflection{
        analysis: "Test analysis",
        root_causes: ["Test cause"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add clarity",
            rationale: "Better understanding",
            priority: :high
          }
        ],
        confidence: :high
      }

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: [reflection])
      assert %FeedbackAggregation.AggregatedFeedback{} = aggregated
      assert aggregated.collection.total_evaluations == 1
    end

    test "aggregates feedback from multiple reflections" do
      reflections = [
        create_reflection(),
        create_reflection(),
        create_reflection()
      ]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert aggregated.collection.total_evaluations == 3
      assert length(aggregated.collection.reflections) == 3
    end

    test "creates feedback collection" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert %FeedbackAggregation.FeedbackCollection{} = aggregated.collection
      assert aggregated.collection.total_evaluations > 0
    end

    test "generates weighted suggestions" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert is_list(aggregated.weighted_suggestions)
    end

    test "partitions by priority" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert is_list(aggregated.high_confidence)
      assert is_list(aggregated.medium_confidence)
      assert is_list(aggregated.low_confidence)
    end

    test "calculates deduplication rate" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert is_float(aggregated.deduplication_rate)
      assert aggregated.deduplication_rate >= 0.0
    end

    test "calculates pattern coverage" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert is_float(aggregated.pattern_coverage)
      assert aggregated.pattern_coverage >= 0.0
    end

    test "includes aggregation timestamp" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert %DateTime{} = aggregated.aggregation_timestamp
    end

    test "includes metadata" do
      reflections = [create_reflection()]

      assert {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(reflections: reflections)
      assert is_map(aggregated.metadata)
    end
  end

  # Helper function
  defp create_reflection do
    %Reflector.ParsedReflection{
      analysis: "Test analysis #{:erlang.unique_integer([:positive])}",
      root_causes: ["Vague instructions", "Missing examples"],
      suggestions: [
        %Reflector.Suggestion{
          type: :add,
          category: :clarity,
          description: "Add step-by-step instructions",
          rationale: "Improves clarity",
          priority: :high,
          specific_text: "Let's solve this step by step"
        },
        %Reflector.Suggestion{
          type: :add,
          category: :constraint,
          description: "Add constraints",
          rationale: "Enforces correctness",
          priority: :medium
        }
      ],
      confidence: :high
    }
  end
end
