defmodule Jido.AI.Accuracy.SelfConsistencyTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.Aggregators.{BestOfN, MajorityVote, Weighted}
  alias Jido.AI.Accuracy.{Candidate, SelfConsistency}
  alias LLMGenerator
  alias Jido.AI.Accuracy.TestSupport.MockGenerator
  alias Jido.AI.Accuracy.SelfConsistencyTestTestHelper

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
      assert {:ok, best, metadata} =
               SelfConsistency.run("What is 2+2?",
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
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1
               )

      assert metadata.aggregator == MajorityVote
    end

    @tag :integration
    @tag :requires_api
    test "resolves :majority_vote to MajorityVote module (requires API)" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 aggregator: :majority_vote,
                 num_candidates: 1
               )

      assert metadata.aggregator == MajorityVote
    end

    @tag :integration
    @tag :requires_api
    test "resolves :best_of_n to BestOfN module (requires API)" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 aggregator: :best_of_n,
                 num_candidates: 1
               )

      assert metadata.aggregator == BestOfN
    end

    @tag :integration
    @tag :requires_api
    test "resolves :weighted to Weighted module (requires API)" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 aggregator: :weighted,
                 num_candidates: 1
               )

      assert metadata.aggregator == Weighted
    end

    @tag :integration
    @tag :requires_api
    test "accepts custom aggregator module (requires API)" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
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
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1
               )

      assert metadata.num_candidates <= 1
    end

    @tag :integration
    @tag :requires_api
    test "accepts temperature_range option (requires API)" do
      assert {:ok, _best, _metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1,
                 temperature_range: {0.5, 0.8}
               )
    end

    @tag :integration
    @tag :requires_api
    test "accepts timeout option (requires API)" do
      assert {:ok, _best, _metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1,
                 timeout: 5000
               )
    end

    @tag :integration
    @tag :requires_api
    test "accepts max_concurrency option (requires API)" do
      assert {:ok, _best, _metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1,
                 max_concurrency: 2
               )
    end

    @tag :integration
    @tag :requires_api
    test "accepts model option (requires API)" do
      assert {:ok, _best, _metadata} =
               SelfConsistency.run("What is 2+2?",
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
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
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
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 num_candidates: 1
               )

      # total_tokens should be nil or a positive integer
      assert metadata.total_tokens == nil or metadata.total_tokens >= 0
    end

    @tag :integration
    @tag :requires_api
    test "includes aggregation_metadata from aggregator (requires API)" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 aggregator: :majority_vote,
                 num_candidates: 1
               )

      assert is_map(metadata.aggregation_metadata)
    end
  end

  describe "error handling" do
    test "handles generation failure gracefully" do
      # Use an invalid timeout to trigger a generation failure
      result =
        SelfConsistency.run("What is 2+2?",
          num_candidates: 1,
          # 1ms timeout should cause failure
          timeout: 1
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
      assert {:ok, best, metadata} =
               SelfConsistency.run_with_reasoning(
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

  describe "prompt sanitization (telemetry)" do
    test "sanitizes email addresses in telemetry" do
      handler_id = :email_sanitization_test
      parent = self()

      :telemetry.attach(
        handler_id,
        [:jido, :accuracy, :self_consistency, :start],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_data, metadata})
        end,
        nil
      )

      # Run with email in prompt
      SelfConsistency.run("Contact me at test@example.com for help", aggregator: String)

      assert_receive {:telemetry_data, metadata}
      # Email should be redacted
      assert String.contains?(metadata.prompt, "[EMAIL]") or
               not String.contains?(metadata.prompt, "@")

      :telemetry.detach(handler_id)
    end

    test "sanitizes phone numbers in telemetry" do
      handler_id = :phone_sanitization_test
      parent = self()

      :telemetry.attach(
        handler_id,
        [:jido, :accuracy, :self_consistency, :start],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_data, metadata})
        end,
        nil
      )

      # Run with phone number
      SelfConsistency.run("Call me at 555-123-4567 for help", aggregator: String)

      assert_receive {:telemetry_data, metadata}
      # Phone should be redacted or truncated
      assert String.contains?(metadata.prompt, "[PHONE]") or
               String.contains?(metadata.prompt, "...")

      :telemetry.detach(handler_id)
    end

    test "truncates long prompts in telemetry" do
      handler_id = :truncation_test
      parent = self()

      :telemetry.attach(
        handler_id,
        [:jido, :accuracy, :self_consistency, :start],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_data, metadata})
        end,
        nil
      )

      # Run with very long prompt
      long_prompt = String.duplicate("a", 200)
      SelfConsistency.run(long_prompt, aggregator: String)

      assert_receive {:telemetry_data, metadata}
      # Prompt should be truncated with "..."
      assert String.length(metadata.prompt) <= 100
      assert String.ends_with?(metadata.prompt, "...")

      :telemetry.detach(handler_id)
    end
  end

  describe "generator validation" do
    test "returns error for invalid generator module" do
      # A module that doesn't implement the Generator behavior
      assert {:error, :invalid_generator} =
               SelfConsistency.run("What is 2+2?", generator: String)
    end

    test "accepts valid generator module implementing Generator behavior" do
      # LLMGenerator implements the Generator behavior
      # This test validates that validation passes for valid modules
      # The error should NOT be :invalid_generator (it would be an exception from actual generation)
      result =
        SelfConsistency.run("What is 2+2?",
          generator: LLMGenerator,
          num_candidates: 1
        )

      # Should not return :invalid_generator error (validation passed)
      refute result == {:error, :invalid_generator}
    end

    test "accepts struct generator" do
      # A struct that implements Generator should be accepted
      # (The validation passes, but we still get error for other reasons)
      generator = LLMGenerator.new!([])
      assert {:error, _} = SelfConsistency.run("What is 2+2?", generator: generator)
    end
  end

  describe "with Mock Generator" do
    test "returns best candidate with majority vote" do
      candidates = [
        Candidate.new!(%{content: "42", model: "mock", tokens_used: 10}),
        Candidate.new!(%{content: "42", model: "mock", tokens_used: 10}),
        Candidate.new!(%{content: "43", model: "mock", tokens_used: 10})
      ]

      generator = MockGenerator.new(candidates: candidates)

      assert {:ok, best, metadata} =
               SelfConsistency.run("What is 2+2?",
                 generator: generator,
                 aggregator: :majority_vote
               )

      assert best.content == "42"
      assert metadata.confidence == 2.0 / 3.0
      assert metadata.num_candidates == 3
    end

    test "returns best candidate with best_of_n aggregator" do
      candidates = [
        Candidate.new!(%{content: "low", model: "mock", tokens_used: 10, score: 0.5}),
        Candidate.new!(%{content: "high", model: "mock", tokens_used: 10, score: 0.9}),
        Candidate.new!(%{content: "medium", model: "mock", tokens_used: 10, score: 0.7})
      ]

      generator = MockGenerator.new(candidates: candidates)

      assert {:ok, best, metadata} =
               SelfConsistency.run("Question",
                 generator: generator,
                 aggregator: :best_of_n
               )

      assert best.content == "high"
      assert best.score == 0.9
    end

    test "handles generation failure gracefully" do
      generator = MockGenerator.new(should_fail: true, failure_reason: :api_error)

      assert {:error, :api_error} =
               SelfConsistency.run("What is 2+2?", generator: generator)
    end

    test "calculates total_tokens correctly" do
      candidates = [
        Candidate.new!(%{content: "a", model: "mock", tokens_used: 10}),
        Candidate.new!(%{content: "b", model: "mock", tokens_used: 20}),
        Candidate.new!(%{content: "c", model: "mock", tokens_used: 30})
      ]

      generator = MockGenerator.new(candidates: candidates)

      assert {:ok, _best, metadata} =
               SelfConsistency.run("Question",
                 generator: generator
               )

      assert metadata.total_tokens == 60
    end

    test "returns nil for total_tokens when all candidates have nil tokens" do
      candidates = [
        Candidate.new!(%{content: "a", model: "mock", tokens_used: nil}),
        Candidate.new!(%{content: "b", model: "mock", tokens_used: nil})
      ]

      generator = MockGenerator.new(candidates: candidates)

      assert {:ok, _best, metadata} =
               SelfConsistency.run("Question",
                 generator: generator
               )

      assert metadata.total_tokens == nil
    end

    test "emits telemetry events on success" do
      candidates = [
        Candidate.new!(%{content: "42", model: "mock", tokens_used: 10}),
        Candidate.new!(%{content: "42", model: "mock", tokens_used: 10})
      ]

      generator = MockGenerator.new(candidates: candidates)

      # Attach telemetry handler
      handler_id = :mock_generator_test
      parent = self()

      :telemetry.attach(
        handler_id,
        [:jido, :accuracy, :self_consistency, :stop],
        fn _event, measurements, _metadata, _ ->
          send(parent, {:stop_event, measurements})
        end,
        nil
      )

      SelfConsistency.run("What is 2+2?", generator: generator)

      assert_receive {:stop_event, %{duration: duration}}
      assert is_integer(duration) and duration >= 0

      :telemetry.detach(handler_id)
    end

    test "emits telemetry events on error" do
      generator = MockGenerator.new(should_fail: true, failure_reason: :test_error)

      # Attach telemetry handler
      handler_id = :mock_generator_error_test
      parent = self()

      :telemetry.attach(
        handler_id,
        [:jido, :accuracy, :self_consistency, :exception],
        fn _event, measurements, metadata, _ ->
          send(parent, {:exception_event, measurements, metadata})
        end,
        nil
      )

      SelfConsistency.run("What is 2+2?", generator: generator)

      assert_receive {:exception_event, %{duration: duration}, %{kind: :error}}
      assert is_integer(duration) and duration >= 0

      :telemetry.detach(handler_id)
    end
  end

  describe "run_with_reasoning/2 with Mock Generator" do
    test "generates candidates with reasoning field" do
      # Mock generator's generate_with_reasoning adds reasoning
      generator = MockGenerator.new(num_candidates: 2)

      assert {:ok, candidates} =
               MockGenerator.generate_with_reasoning(generator, "What is 2+2?")

      assert length(candidates) == 2

      # Check that reasoning is added
      Enum.each(candidates, fn c ->
        assert Map.has_key?(c, :reasoning)
        assert is_binary(c.reasoning)
      end)
    end

    test "propagates generation errors" do
      generator = MockGenerator.new(should_fail: true, failure_reason: :generation_failed)

      assert {:error, :generation_failed} =
               MockGenerator.generate_with_reasoning(generator, "Question")
    end
  end

  # Helper functions

  defp attach_telemetry_handler(pid, event_name) do
    handler_id = String.to_atom("test_handler_#{event_name}")

    :telemetry.attach(
      handler_id,
      [:jido, :accuracy, :self_consistency, event_name],
      &SelfConsistencyTestTestHelper.handle_event/4,
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
