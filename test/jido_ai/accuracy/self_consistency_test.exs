defmodule Jido.AI.Accuracy.SelfConsistencyTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.{Candidate, SelfConsistency}
  alias Jido.AI.Accuracy.Aggregators.{MajorityVote, BestOfN, Weighted}

  @moduletag :capture_log

  describe "run/2" do
    test "returns error with invalid aggregator atom" do
      # An atom that doesn't map to any aggregator
      result = SelfConsistency.run("What is 2+2?", aggregator: :non_existent_aggregator)
      # Should return error since the module doesn't exist or doesn't have aggregate/2
      assert {:error, _reason} = result
    end

    test "validates aggregator module before running" do
      # Pass an invalid module (doesn't implement aggregate/2)
      assert {:error, :invalid_aggregator} =
        SelfConsistency.run("What is 2+2?", aggregator: String)
    end

    @tag :integration
    @tag :requires_api
    test "generates and aggregates candidates (requires API)" do
      assert {:ok, best, metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1
      )

      assert %Candidate{} = best
      assert is_number(metadata.confidence)
      assert is_integer(metadata.num_candidates)
    end
  end

  describe "aggregator selection" do
    @tag :integration
    @tag :requires_api
    test "uses majority_vote by default (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1
      )

      assert metadata.aggregator == MajorityVote
    end

    @tag :integration
    @tag :requires_api
    test "resolves :majority_vote to MajorityVote module (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        aggregator: :majority_vote,
        num_candidates: 1
      )

      assert metadata.aggregator == MajorityVote
    end

    @tag :integration
    @tag :requires_api
    test "resolves :best_of_n to BestOfN module (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        aggregator: :best_of_n,
        num_candidates: 1
      )

      assert metadata.aggregator == BestOfN
    end

    @tag :integration
    @tag :requires_api
    test "resolves :weighted to Weighted module (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        aggregator: :weighted,
        num_candidates: 1
      )

      assert metadata.aggregator == Weighted
    end

    @tag :integration
    @tag :requires_api
    test "accepts custom aggregator module (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        aggregator: BestOfN,
        num_candidates: 1
      )

      assert metadata.aggregator == BestOfN
    end
  end

  describe "configuration" do
    @tag :integration
    @tag :requires_api
    test "passes num_candidates to generator (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1
      )

      assert metadata.num_candidates <= 1
    end

    @tag :integration
    @tag :requires_api
    test "accepts temperature_range option (requires API)" do
      assert {:ok, _best, _metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1,
        temperature_range: {0.5, 0.8}
      )
    end

    @tag :integration
    @tag :requires_api
    test "accepts timeout option (requires API)" do
      assert {:ok, _best, _metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1,
        timeout: 5000
      )
    end

    @tag :integration
    @tag :requires_api
    test "accepts max_concurrency option (requires API)" do
      assert {:ok, _best, _metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1,
        max_concurrency: 2
      )
    end

    @tag :integration
    @tag :requires_api
    test "accepts model option (requires API)" do
      assert {:ok, _best, _metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1,
        model: "anthropic:claude-haiku-4-5"
      )
    end
  end

  describe "telemetry" do
    test "emits start event" do
      attach_telemetry_handler(self(), :start)

      # This will fail on API but should still emit start event
      SelfConsistency.run("What is 2+2?", aggregator: String)

      assert_received {:telemetry_event, [:jido, :accuracy, :self_consistency, :start], _measurements, metadata}
      assert Map.has_key?(metadata, :prompt)
      assert Map.has_key?(metadata, :num_candidates)
      assert Map.has_key?(metadata, :aggregator)
    end

    test "emits exception event on error" do
      attach_telemetry_handler(self(), :exception)

      SelfConsistency.run("What is 2+2?", aggregator: String)

      assert_received {:telemetry_event, [:jido, :accuracy, :self_consistency, :exception], measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert metadata.kind == :error
    end

    @tag :integration
    @tag :requires_api
    test "emits stop event on success (requires API)" do
      attach_telemetry_handler(self(), :stop)

      SelfConsistency.run("What is 2+2?", num_candidates: 1)

      assert_received {:telemetry_event, [:jido, :accuracy, :self_consistency, :stop], measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert Map.has_key?(metadata, :num_candidates)
      assert Map.has_key?(metadata, :confidence)
    end
  end

  describe "metadata" do
    @tag :integration
    @tag :requires_api
    test "returns correct metadata structure (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1
      )

      # Required fields
      assert Map.has_key?(metadata, :confidence)
      assert Map.has_key?(metadata, :num_candidates)
      assert Map.has_key?(metadata, :aggregator)
      assert Map.has_key?(metadata, :total_tokens)
      assert Map.has_key?(metadata, :aggregation_metadata)

      # Types
      assert is_number(metadata.confidence)
      assert is_integer(metadata.num_candidates)
      assert is_atom(metadata.aggregator)
    end

    @tag :integration
    @tag :requires_api
    test "calculates total_tokens correctly (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        num_candidates: 1
      )

      # total_tokens should be nil or a positive integer
      assert metadata.total_tokens == nil or metadata.total_tokens >= 0
    end

    @tag :integration
    @tag :requires_api
    test "includes aggregation_metadata from aggregator (requires API)" do
      assert {:ok, _best, metadata} = SelfConsistency.run("What is 2+2?",
        aggregator: :majority_vote,
        num_candidates: 1
      )

      assert is_map(metadata.aggregation_metadata)
    end
  end

  describe "error handling" do
    test "handles generation failure gracefully" do
      # Use an invalid timeout to trigger a generation failure
      result = SelfConsistency.run("What is 2+2?",
        num_candidates: 1,
        timeout: 1  # 1ms timeout should cause failure
      )

      # Should either succeed or return an error, not crash
      case result do
        {:ok, _best, _metadata} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "run_with_reasoning/2" do
    @tag :integration
    @tag :requires_api
    test "generates candidates with CoT prompt (requires API)" do
      assert {:ok, best, metadata} = SelfConsistency.run_with_reasoning(
        "Solve step by step: 2+2",
        num_candidates: 1
      )

      # Verify metadata structure
      assert is_number(metadata.confidence)
      assert metadata.num_candidates == 1
      # The reasoning field may be empty or populated depending on LLM response
      assert %Candidate{} = best
    end
  end

  # Helper functions

  defp attach_telemetry_handler(pid, event_name) do
    handler_id = String.to_atom("test_handler_#{event_name}")

    :telemetry.attach(
      handler_id,
      [:jido, :accuracy, :self_consistency, event_name],
      &Jido.AI.Accuracy.SelfConsistencyTestTestHelper.handle_event/4,
      pid
    )
  end
end

# Telemetry handler module helper
defmodule Jido.AI.Accuracy.SelfConsistencyTestTestHelper do
  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
