defmodule Jido.AI.Accuracy.AdaptiveSelfConsistencySecurityTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.{AdaptiveSelfConsistency, DifficultyEstimate, Candidate}
  alias Uniq.UUID

  @moduletag :security
  @moduletag :adaptive_self_consistency

  describe "empty candidate handling" do
    setup do
      adapter = AdaptiveSelfConsistency.new!(%{})
      %{adapter: adapter}
    end

    test "returns error when all generators fail", %{adapter: adapter} do
      # Generator that always fails
      failing_generator = fn _query ->
        {:error, :generation_failed}
      end

      assert {:error, :all_generators_failed} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: failing_generator
               )
    end

    test "returns error when generator returns nil candidates", %{adapter: adapter} do
      # Generator that returns invalid response
      nil_generator = fn _query ->
        {:ok, nil}
      end

      assert {:error, :all_generators_failed} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: nil_generator
               )
    end

    test "handles partial failures gracefully", %{adapter: adapter} do
      # Use an Agent instead of :atomics for counting
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      # Generator that fails first 2 calls, then succeeds
      eventual_generator = fn _query ->
        count = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)

        if count <= 2 do
          {:error, :temporary_failure}
        else
          {:ok,
           Candidate.new!(%{
             id: UUID.uuid4(),
             content: "4",
             model: "test"
           })}
        end
      end

      # Should succeed after retries
      result =
        AdaptiveSelfConsistency.run(
          adapter,
          "What is 2+2?",
          generator: eventual_generator
        )

      Agent.stop(counter)

      assert {:ok, _result, _metadata} = result
    end
  end

  describe "generator validation" do
    setup do
      adapter = AdaptiveSelfConsistency.new!(%{})
      %{adapter: adapter}
    end

    test "rejects non-function generators", %{adapter: adapter} do
      assert {:error, :generator_required} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: "not_a_function"
               )

      assert {:error, :generator_required} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: nil
               )

      assert {:error, :generator_required} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: %{}
               )
    end

    test "handles generators that return nil candidates gracefully", %{adapter: adapter} do
      nil_generator = fn _query ->
        {:ok, nil}
      end

      # Generator returns nil candidate
      # This gets filtered out and results in all_generators_failed
      assert {:error, :all_generators_failed} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 generator: nil_generator
               )
    end
  end

  describe "query validation" do
    setup do
      adapter = AdaptiveSelfConsistency.new!(%{})
      %{adapter: adapter}
    end

    test "requires binary queries - non-binary raises error", %{adapter: adapter} do
      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: UUID.uuid4(),
           content: "4",
           model: "test"
         })}
      end

      # Non-binary queries will fail function clause matching
      assert_raise FunctionClauseError, fn ->
        AdaptiveSelfConsistency.run(adapter, 123, generator: generator)
      end

      assert_raise FunctionClauseError, fn ->
        AdaptiveSelfConsistency.run(adapter, nil, generator: generator)
      end
    end
  end

  describe "configuration validation" do
    test "rejects invalid min_candidates" do
      assert {:error, {_field, :must_be_positive}} =
               AdaptiveSelfConsistency.new(%{min_candidates: 0})

      assert {:error, {_field, :must_be_positive}} =
               AdaptiveSelfConsistency.new(%{min_candidates: -1})
    end

    test "rejects invalid max_candidates" do
      assert {:error, {_field, :must_be_positive}} =
               AdaptiveSelfConsistency.new(%{max_candidates: 0})

      assert {:error, {_field, :must_be_positive}} =
               AdaptiveSelfConsistency.new(%{max_candidates: -5})
    end

    test "rejects min > max candidates" do
      assert {:error, :min_candidates_must_be_less_than_max} =
               AdaptiveSelfConsistency.new(%{
                 min_candidates: 10,
                 max_candidates: 5
               })
    end

    test "rejects invalid early_stop_threshold" do
      assert {:error, :early_stop_threshold_must_be_between_0_and_1} =
               AdaptiveSelfConsistency.new(%{early_stop_threshold: -0.1})

      assert {:error, :early_stop_threshold_must_be_between_0_and_1} =
               AdaptiveSelfConsistency.new(%{early_stop_threshold: 1.1})
    end

    test "rejects invalid aggregator module" do
      assert {:error, :aggregator_must_implement_aggregate} =
               AdaptiveSelfConsistency.new(%{aggregator: String})
    end
  end

  describe "N adjustment validation" do
    test "respects max_candidates limit" do
      # Even for hard difficulty, max should be capped at adapter's max
      assert AdaptiveSelfConsistency.max_n_for_level(:hard) == 20

      # Creating adapter with different max_candidates
      assert {:ok, _adapter} = AdaptiveSelfConsistency.new(%{max_candidates: 3})
    end

    test "handles edge case of batch_size > remaining" do
      # When current_n + batch_size would exceed max_n
      # adjust_n_batch should return remaining count
      assert AdaptiveSelfConsistency.adjust_n(:easy, 4, max_n: 5) == 1
      assert AdaptiveSelfConsistency.adjust_n(:easy, 5, max_n: 5) == 0
    end
  end

  describe "consensus checking security" do
    test "handles empty candidates list" do
      assert {:error, :no_candidates} =
               AdaptiveSelfConsistency.check_consensus([])
    end

    test "handles single candidate" do
      candidate =
        Candidate.new!(%{
          id: UUID.uuid4(),
          content: "4",
          model: "test"
        })

      assert {:ok, 1.0, _metadata} =
               AdaptiveSelfConsistency.check_consensus([candidate])
    end
  end

  describe "metadata integrity" do
    setup do
      adapter = AdaptiveSelfConsistency.new!(%{})
      %{adapter: adapter}
    end

    test "includes actual_n in metadata", %{adapter: adapter} do
      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: UUID.uuid4(),
           content: "Answer 4",
           model: "test"
         })}
      end

      assert {:ok, _result, metadata} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 difficulty_level: :easy,
                 generator: generator
               )

      assert is_integer(metadata.actual_n)
      assert metadata.actual_n >= 3
    end

    test "includes early_stopped flag in metadata", %{adapter: adapter} do
      # Consistent generator triggers early stopping
      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: UUID.uuid4(),
           content: "The answer is 4",
           model: "test"
         })}
      end

      assert {:ok, _result, metadata} =
               AdaptiveSelfConsistency.run(
                 adapter,
                 "What is 2+2?",
                 difficulty_level: :easy,
                 generator: generator
               )

      assert is_boolean(metadata.early_stopped)
      assert Map.has_key?(metadata, :consensus)
    end
  end
end
