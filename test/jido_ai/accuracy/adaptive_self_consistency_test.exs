defmodule Jido.AI.Accuracy.AdaptiveSelfConsistencyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{AdaptiveSelfConsistency, Candidate, DifficultyEstimate}

  doctest AdaptiveSelfConsistency

  describe "new/1" do
    test "creates adapter with default values" do
      assert {:ok, adapter} = AdaptiveSelfConsistency.new(%{})
      assert adapter.min_candidates == 3
      assert adapter.max_candidates == 20
      assert adapter.batch_size == 3
      assert adapter.early_stop_threshold == 0.8
    end

    test "creates adapter with custom values" do
      assert {:ok, adapter} =
               AdaptiveSelfConsistency.new(%{
                 min_candidates: 5,
                 max_candidates: 15,
                 batch_size: 5,
                 early_stop_threshold: 0.9
               })

      assert adapter.min_candidates == 5
      assert adapter.max_candidates == 15
      assert adapter.batch_size == 5
      assert adapter.early_stop_threshold == 0.9
    end

    test "returns error for invalid min_candidates" do
      assert {:error, {:min_candidates, :must_be_positive}} = AdaptiveSelfConsistency.new(%{min_candidates: 0})
      assert {:error, {:min_candidates, :must_be_positive}} = AdaptiveSelfConsistency.new(%{min_candidates: -1})
    end

    test "returns error for invalid max_candidates" do
      assert {:error, {:max_candidates, :must_be_positive}} = AdaptiveSelfConsistency.new(%{max_candidates: 0})
    end

    test "returns error for min > max" do
      assert {:error, :min_candidates_must_be_less_than_max} =
               AdaptiveSelfConsistency.new(%{min_candidates: 10, max_candidates: 5})
    end

    test "returns error for invalid threshold" do
      assert {:error, :early_stop_threshold_must_be_between_0_and_1} =
               AdaptiveSelfConsistency.new(%{early_stop_threshold: -0.1})

      assert {:error, :early_stop_threshold_must_be_between_0_and_1} =
               AdaptiveSelfConsistency.new(%{early_stop_threshold: 1.1})
    end

    test "returns error for invalid batch_size" do
      assert {:error, {:batch_size, :must_be_positive}} = AdaptiveSelfConsistency.new(%{batch_size: 0})
    end
  end

  describe "new!/1" do
    test "returns adapter with valid settings" do
      adapter = AdaptiveSelfConsistency.new!(%{min_candidates: 5})
      assert adapter.min_candidates == 5
    end

    test "raises on invalid settings" do
      assert_raise ArgumentError, ~r/Invalid AdaptiveSelfConsistency/, fn ->
        AdaptiveSelfConsistency.new!(%{min_candidates: 0})
      end
    end
  end

  describe "initial_n_for_level/1" do
    test "returns 3 for easy" do
      assert AdaptiveSelfConsistency.initial_n_for_level(:easy) == 3
    end

    test "returns 5 for medium" do
      assert AdaptiveSelfConsistency.initial_n_for_level(:medium) == 5
    end

    test "returns 10 for hard" do
      assert AdaptiveSelfConsistency.initial_n_for_level(:hard) == 10
    end
  end

  describe "max_n_for_level/1" do
    test "returns 5 for easy" do
      assert AdaptiveSelfConsistency.max_n_for_level(:easy) == 5
    end

    test "returns 10 for medium" do
      assert AdaptiveSelfConsistency.max_n_for_level(:medium) == 10
    end

    test "returns 20 for hard" do
      assert AdaptiveSelfConsistency.max_n_for_level(:hard) == 20
    end
  end

  describe "adjust_n/3" do
    test "returns batch size when below max" do
      assert AdaptiveSelfConsistency.adjust_n(:easy, 0, max_n: 5) == 3
      assert AdaptiveSelfConsistency.adjust_n(:easy, 3, max_n: 5) == 2
    end

    test "returns 0 when at max" do
      assert AdaptiveSelfConsistency.adjust_n(:easy, 5, max_n: 5) == 0
      assert AdaptiveSelfConsistency.adjust_n(:easy, 6, max_n: 5) == 0
    end

    test "respects custom batch size" do
      assert AdaptiveSelfConsistency.adjust_n(:easy, 0, batch_size: 5) == 5
    end

    test "handles partial batch near max" do
      assert AdaptiveSelfConsistency.adjust_n(:easy, 4, max_n: 5) == 1
    end
  end

  describe "check_consensus/2" do
    setup do
      # Create mock candidates with consistent answers
      consistent_candidates =
        for i <- 1..3 do
          Candidate.new!(%{
            id: "candidate_#{i}",
            content: "The answer is: 42",
            model: "test"
          })
        end

      # Create mock candidates with split answers
      split_candidates = [
        Candidate.new!(%{id: "c1", content: "The answer is: 42", model: "test"}),
        Candidate.new!(%{id: "c2", content: "The answer is: 42", model: "test"}),
        Candidate.new!(%{id: "c3", content: "The answer is: 41", model: "test"})
      ]

      {:ok, consistent: consistent_candidates, split: split_candidates}
    end

    test "returns high consensus for consistent candidates", context do
      assert {:ok, agreement, _metadata} =
               AdaptiveSelfConsistency.check_consensus(context.consistent)

      assert agreement >= 0.8
    end

    test "returns low consensus for split candidates", context do
      assert {:ok, agreement, _metadata} =
               AdaptiveSelfConsistency.check_consensus(context.split)

      assert agreement < 1.0
    end

    test "returns error for empty candidate list" do
      assert {:error, :no_candidates} = AdaptiveSelfConsistency.check_consensus([])
    end
  end

  describe "consensus_reached?/2" do
    setup do
      consistent_candidates =
        for i <- 1..4 do
          Candidate.new!(%{
            id: "candidate_#{i}",
            content: "The answer is: 42",
            model: "test"
          })
        end

      split_candidates = [
        Candidate.new!(%{id: "c1", content: "The answer is: 42", model: "test"}),
        Candidate.new!(%{id: "c2", content: "The answer is: 42", model: "test"}),
        Candidate.new!(%{id: "c3", content: "The answer is: 41", model: "test"}),
        Candidate.new!(%{id: "c4", content: "The answer is: 40", model: "test"})
      ]

      {:ok, consistent: consistent_candidates, split: split_candidates}
    end

    test "returns true when consensus >= threshold", context do
      assert {:ok, true} = AdaptiveSelfConsistency.consensus_reached?(context.consistent, 0.8)
    end

    test "returns false when consensus < threshold", context do
      assert {:ok, false} = AdaptiveSelfConsistency.consensus_reached?(context.split, 0.8)
    end

    test "returns true with lower threshold", context do
      assert {:ok, true} = AdaptiveSelfConsistency.consensus_reached?(context.split, 0.5)
    end
  end

  describe "run/3" do
    setup do
      adapter =
        AdaptiveSelfConsistency.new!(%{
          min_candidates: 3,
          max_candidates: 10,
          batch_size: 3,
          early_stop_threshold: 0.8
        })

      # Create a simple generator that returns mock candidates
      simple_generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           content: "The answer is: 42",
           model: "test"
         })}
      end

      {:ok, adapter: adapter, generator: simple_generator}
    end

    test "generates candidates with easy difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})

      {:ok, result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "What is 2+2?",
          difficulty_estimate: estimate,
          generator: context.generator
        )

      assert result != nil
      assert is_map(metadata)
      assert metadata.actual_n > 0
      assert metadata.actual_n <= context.adapter.max_candidates
      assert Map.has_key?(metadata, :early_stopped)
      assert Map.has_key?(metadata, :consensus)
    end

    test "generates candidates with medium difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      # Use varied generator to prevent early stopping for this test
      varied_generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           # Varied content
           content: "Answer #{:rand.uniform()}",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Explain photosynthesis",
          difficulty_estimate: estimate,
          generator: varied_generator
        )

      # With varied content and no early stopping, should generate initial_n for medium
      assert metadata.actual_n >= 5
      assert metadata.actual_n <= 10
    end

    test "generates candidates with hard difficulty", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :hard, score: 0.8})

      # Use varied generator to prevent early stopping for this test
      varied_generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           # Varied content
           content: "Answer #{:rand.uniform()}",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Prove the Riemann hypothesis",
          difficulty_estimate: estimate,
          generator: varied_generator
        )

      # With varied content and no early stopping, should generate initial_n for hard
      assert metadata.actual_n >= 10
      assert metadata.actual_n <= 20
    end

    test "uses difficulty_level atom when no estimate provided", context do
      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Test query",
          difficulty_level: :easy,
          generator: context.generator
        )

      assert metadata.actual_n >= 3
      assert metadata.actual_n <= 5
    end

    test "defaults to medium when no difficulty info", context do
      # Use varied generator to prevent early stopping for this test
      varied_generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           # Varied content
           content: "Answer #{:rand.uniform()}",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Test query",
          generator: varied_generator
        )

      # Default is medium, should generate initial_n for medium
      assert metadata.actual_n >= 5
      assert metadata.actual_n <= 10
    end

    test "returns error without generator", context do
      assert {:error, :generator_required} =
               AdaptiveSelfConsistency.run(context.adapter, "Test query", [])
    end

    test "includes early_stopped in metadata", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Test",
          difficulty_estimate: estimate,
          generator: context.generator
        )

      assert is_boolean(metadata.early_stopped)
    end

    test "includes consensus in metadata", context do
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          context.adapter,
          "Test",
          difficulty_estimate: estimate,
          generator: context.generator
        )

      assert is_number(metadata.consensus) or is_nil(metadata.consensus)
    end
  end

  describe "early stopping behavior" do
    test "stops early when consensus threshold is reached" do
      adapter =
        AdaptiveSelfConsistency.new!(%{
          min_candidates: 3,
          max_candidates: 10,
          batch_size: 3,
          early_stop_threshold: 0.8
        })

      # Generator that produces consistent answers
      consistent_generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           content: "The answer is: 42",
           model: "test"
         })}
      end

      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          adapter,
          "Test",
          difficulty_estimate: estimate,
          generator: consistent_generator
        )

      # Should stop early due to consensus
      assert metadata.early_stopped == true
      # Should have generated exactly min_candidates since all agree
      assert metadata.actual_n == 3
    end
  end

  describe "consistency with difficulty-based N" do
    test "easy difficulty generates fewer candidates" do
      adapter =
        AdaptiveSelfConsistency.new!(%{
          min_candidates: 3,
          max_candidates: 5,
          batch_size: 3
        })

      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           content: "Answer",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          adapter,
          "Test",
          difficulty_level: :easy,
          generator: generator
        )

      assert metadata.actual_n <= 5
      assert metadata.initial_n == 3
      assert metadata.max_n == 5
    end

    test "hard difficulty generates more candidates" do
      adapter =
        AdaptiveSelfConsistency.new!(%{
          min_candidates: 10,
          max_candidates: 20,
          batch_size: 5
        })

      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           content: "Answer",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          adapter,
          "Test",
          difficulty_level: :hard,
          generator: generator
        )

      assert metadata.actual_n >= 10
      assert metadata.initial_n == 10
      assert metadata.max_n == 20
    end
  end

  describe "metadata accuracy" do
    test "metadata includes all required fields" do
      adapter =
        AdaptiveSelfConsistency.new!(%{
          min_candidates: 3,
          max_candidates: 10,
          early_stop_threshold: 0.8
        })

      generator = fn _query ->
        {:ok,
         Candidate.new!(%{
           id: Uniq.UUID.uuid4(),
           content: "Answer",
           model: "test"
         })}
      end

      {:ok, _result, metadata} =
        AdaptiveSelfConsistency.run(
          adapter,
          "Test",
          difficulty_level: :medium,
          generator: generator
        )

      # Check all required metadata fields
      assert Map.has_key?(metadata, :actual_n)
      assert Map.has_key?(metadata, :early_stopped)
      assert Map.has_key?(metadata, :consensus)
      assert Map.has_key?(metadata, :initial_n)
      assert Map.has_key?(metadata, :max_n)

      # Verify types
      assert is_integer(metadata.actual_n)
      assert is_boolean(metadata.early_stopped)
      assert metadata.actual_n > 0
    end
  end
end
