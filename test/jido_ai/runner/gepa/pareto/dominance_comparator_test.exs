defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate

  # Test helper to create candidate with normalized objectives
  defp make_candidate(id, objectives) do
    %Candidate{
      id: id,
      prompt: "test prompt #{id}",
      generation: 1,
      created_at: System.monotonic_time(:millisecond),
      normalized_objectives: objectives
    }
  end

  describe "compare/3" do
    test "returns :dominates when A is better in all objectives" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.6})

      assert DominanceComparator.compare(a, b) == :dominates
    end

    test "returns :dominates when A is equal in some and better in others" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8, cost: 0.7})
      b = make_candidate("b", %{accuracy: 0.9, latency: 0.6, cost: 0.7})

      assert DominanceComparator.compare(a, b) == :dominates
    end

    test "returns :dominated_by when B is better in all objectives" do
      a = make_candidate("a", %{accuracy: 0.5, latency: 0.4})
      b = make_candidate("b", %{accuracy: 0.9, latency: 0.8})

      assert DominanceComparator.compare(a, b) == :dominated_by
    end

    test "returns :non_dominated when solutions trade off" do
      # A better in accuracy, B better in latency
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      assert DominanceComparator.compare(a, b) == :non_dominated
    end

    test "returns :non_dominated when solutions are identical" do
      a = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.7})

      assert DominanceComparator.compare(a, b) == :non_dominated
    end

    test "handles candidate with no normalized_objectives gracefully" do
      a = make_candidate("a", %{accuracy: 0.8})

      b = %Candidate{
        id: "b",
        prompt: "test",
        generation: 1,
        created_at: System.monotonic_time(:millisecond),
        normalized_objectives: nil
      }

      assert DominanceComparator.compare(a, b) == :non_dominated
      assert DominanceComparator.compare(b, a) == :non_dominated
    end

    test "handles empty objectives map" do
      a = make_candidate("a", %{})
      b = make_candidate("b", %{})

      assert DominanceComparator.compare(a, b) == :non_dominated
    end

    test "works with different objective sets" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      b = make_candidate("b", %{accuracy: 0.7, cost: 0.6})

      # A better in accuracy, but missing cost; B has cost but worse accuracy
      result = DominanceComparator.compare(a, b)
      assert result in [:dominates, :non_dominated]
    end

    test "handles four standard objectives" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8, cost: 0.7, robustness: 0.85})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.6, cost: 0.5, robustness: 0.75})

      assert DominanceComparator.compare(a, b) == :dominates
    end

    test "complex trade-off with four objectives" do
      # A better in accuracy and cost, B better in latency and robustness
      a = make_candidate("a", %{accuracy: 0.95, latency: 0.5, cost: 0.9, robustness: 0.6})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.9, cost: 0.7, robustness: 0.95})

      assert DominanceComparator.compare(a, b) == :non_dominated
    end
  end

  describe "dominates?/3" do
    test "returns true when A dominates B" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.6})

      assert DominanceComparator.dominates?(a, b) == true
    end

    test "returns false when B dominates A" do
      a = make_candidate("a", %{accuracy: 0.7, latency: 0.6})
      b = make_candidate("b", %{accuracy: 0.9, latency: 0.8})

      assert DominanceComparator.dominates?(a, b) == false
    end

    test "returns false when neither dominates" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      assert DominanceComparator.dominates?(a, b) == false
    end
  end

  describe "fast_non_dominated_sort/2" do
    test "returns empty map for empty population" do
      assert DominanceComparator.fast_non_dominated_sort([]) == %{}
    end

    test "returns single front for single candidate" do
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})

      fronts = DominanceComparator.fast_non_dominated_sort([candidate])

      assert map_size(fronts) == 1
      assert length(fronts[1]) == 1
      assert hd(fronts[1]).id == "a"
    end

    test "classifies two non-dominated candidates into front 1" do
      # Trade-off: A better accuracy, B better latency
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b])

      assert map_size(fronts) == 1
      assert length(fronts[1]) == 2
      ids = Enum.map(fronts[1], & &1.id) |> Enum.sort()
      assert ids == ["a", "b"]
    end

    test "classifies dominated candidate into front 2" do
      # A dominates C, B dominates C, but A and B are non-dominated
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})
      c = make_candidate("c", %{accuracy: 0.6, latency: 0.4})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b, c])

      assert map_size(fronts) == 2
      assert length(fronts[1]) == 2
      assert length(fronts[2]) == 1
      assert hd(fronts[2]).id == "c"
    end

    test "classifies population with multiple fronts" do
      # Front 1: a, b (non-dominated, trade-off)
      # Front 2: c, d (dominated by front 1, but trade-off with each other)
      # Front 3: e (dominated by fronts 1 and 2)
      a = make_candidate("a", %{accuracy: 0.95, latency: 0.6})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.9})
      c = make_candidate("c", %{accuracy: 0.85, latency: 0.5})
      d = make_candidate("d", %{accuracy: 0.7, latency: 0.8})
      e = make_candidate("e", %{accuracy: 0.6, latency: 0.4})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b, c, d, e])

      assert map_size(fronts) >= 2
      assert length(fronts[1]) == 2
      front_1_ids = Enum.map(fronts[1], & &1.id) |> Enum.sort()
      assert front_1_ids == ["a", "b"]
    end

    test "handles all identical candidates" do
      candidates = [
        make_candidate("a", %{accuracy: 0.8, latency: 0.7}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.7}),
        make_candidate("c", %{accuracy: 0.8, latency: 0.7})
      ]

      fronts = DominanceComparator.fast_non_dominated_sort(candidates)

      # All identical = all non-dominated
      assert map_size(fronts) == 1
      assert length(fronts[1]) == 3
    end

    test "handles population with clear dominance hierarchy" do
      # Linear dominance: a > b > c > d
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.9})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.7})
      c = make_candidate("c", %{accuracy: 0.5, latency: 0.5})
      d = make_candidate("d", %{accuracy: 0.3, latency: 0.3})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b, c, d])

      assert map_size(fronts) == 4
      assert hd(fronts[1]).id == "a"
      assert hd(fronts[2]).id == "b"
      assert hd(fronts[3]).id == "c"
      assert hd(fronts[4]).id == "d"
    end

    test "handles large population with multiple objectives" do
      candidates =
        for i <- 1..20 do
          # Create varied candidates with trade-offs
          # 0.5-1.0
          acc = :rand.uniform() * 0.5 + 0.5
          # 0.5-1.0
          lat = :rand.uniform() * 0.5 + 0.5
          make_candidate("candidate_#{i}", %{accuracy: acc, latency: lat})
        end

      fronts = DominanceComparator.fast_non_dominated_sort(candidates)

      # Should have at least 1 front
      assert map_size(fronts) >= 1

      # All candidates should be classified
      total_classified = fronts |> Map.values() |> List.flatten() |> length()
      assert total_classified == 20

      # Front numbers should be sequential starting from 1
      front_numbers = Map.keys(fronts) |> Enum.sort()
      assert hd(front_numbers) == 1
      assert front_numbers == Enum.to_list(1..length(front_numbers))
    end

    test "handles candidates with missing objectives" do
      a = make_candidate("a", %{accuracy: 0.9})
      b = make_candidate("b", %{latency: 0.8})
      c = make_candidate("c", %{accuracy: 0.7, latency: 0.6})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b, c])

      # Should complete without error
      assert is_map(fronts)
      assert map_size(fronts) >= 1
    end
  end

  describe "crowding_distance/2" do
    test "returns empty map for empty population" do
      assert DominanceComparator.crowding_distance([]) == %{}
    end

    test "returns infinity for single candidate" do
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})

      distances = DominanceComparator.crowding_distance([candidate])

      assert distances["a"] == :infinity
    end

    test "returns infinity for both candidates when only two" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      distances = DominanceComparator.crowding_distance([a, b])

      assert distances["a"] == :infinity
      assert distances["b"] == :infinity
    end

    test "calculates distances for three candidates" do
      # Boundary: a (best accuracy), c (best latency)
      # Interior: b (middle)
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.7})
      c = make_candidate("c", %{accuracy: 0.7, latency: 0.9})

      distances = DominanceComparator.crowding_distance([a, b, c])

      # Boundary solutions should have infinite distance
      assert distances["a"] == :infinity
      assert distances["c"] == :infinity

      # Interior solution should have finite distance > 0
      assert is_float(distances["b"])
      assert distances["b"] > 0.0
    end

    test "calculates distances for multiple interior solutions" do
      candidates = [
        # Boundary
        make_candidate("a", %{accuracy: 1.0, latency: 0.0}),
        # Interior
        make_candidate("b", %{accuracy: 0.8, latency: 0.2}),
        # Interior
        make_candidate("c", %{accuracy: 0.6, latency: 0.4}),
        # Interior
        make_candidate("d", %{accuracy: 0.4, latency: 0.6}),
        # Boundary
        make_candidate("e", %{accuracy: 0.0, latency: 1.0})
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # Boundary solutions
      assert distances["a"] == :infinity
      assert distances["e"] == :infinity

      # Interior solutions should have positive finite distances
      assert is_float(distances["b"]) and distances["b"] > 0.0
      assert is_float(distances["c"]) and distances["c"] > 0.0
      assert is_float(distances["d"]) and distances["d"] > 0.0

      # More isolated solutions should have higher crowding distance
      # b and d are more isolated than c (which is in the middle)
      assert distances["b"] > distances["c"] or distances["d"] > distances["c"]
    end

    test "handles identical objective values gracefully" do
      # All candidates have same accuracy, different latency
      candidates = [
        make_candidate("a", %{accuracy: 0.8, latency: 0.3}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.6}),
        make_candidate("c", %{accuracy: 0.8, latency: 0.9})
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # Should complete without error
      assert is_map(distances)
      # Boundary solutions should still have infinity
      assert distances["a"] == :infinity
      assert distances["c"] == :infinity
    end

    test "handles all identical candidates" do
      candidates = [
        make_candidate("a", %{accuracy: 0.8, latency: 0.7}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.7}),
        make_candidate("c", %{accuracy: 0.8, latency: 0.7})
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # All should get infinite distance (or all zero, implementation dependent)
      assert is_map(distances)
      assert map_size(distances) == 3
    end

    test "calculates distances with four objectives" do
      candidates = [
        make_candidate("a", %{accuracy: 0.9, latency: 0.5, cost: 0.7, robustness: 0.8}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.6, cost: 0.8, robustness: 0.7}),
        make_candidate("c", %{accuracy: 0.7, latency: 0.7, cost: 0.9, robustness: 0.6})
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # With multiple objectives, distances accumulate
      assert distances["a"] == :infinity
      assert distances["c"] == :infinity
      assert is_float(distances["b"])
    end

    test "handles candidates with no normalized_objectives" do
      candidates = [
        %Candidate{
          id: "a",
          prompt: "test",
          generation: 1,
          created_at: System.monotonic_time(:millisecond),
          normalized_objectives: nil
        }
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # Should handle gracefully
      assert distances["a"] == :infinity
    end

    test "larger crowding distance for more isolated solutions" do
      # Create a front with uneven spacing
      candidates = [
        # Boundary
        make_candidate("a", %{accuracy: 1.0, latency: 0.0}),
        # Close to a
        make_candidate("b", %{accuracy: 0.9, latency: 0.1}),
        # Far from others
        make_candidate("c", %{accuracy: 0.5, latency: 0.5}),
        # Close to e
        make_candidate("d", %{accuracy: 0.1, latency: 0.9}),
        # Boundary
        make_candidate("e", %{accuracy: 0.0, latency: 1.0})
      ]

      distances = DominanceComparator.crowding_distance(candidates)

      # c is more isolated, so should have higher distance than b or d
      assert distances["c"] > distances["b"]
      assert distances["c"] > distances["d"]
    end
  end

  describe "epsilon_dominates?/3" do
    test "returns false when A does not dominate B" do
      a = make_candidate("a", %{accuracy: 0.7, latency: 0.6})
      b = make_candidate("b", %{accuracy: 0.9, latency: 0.8})

      refute DominanceComparator.epsilon_dominates?(a, b)
    end

    test "returns true when A strictly dominates B with default epsilon" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.6})

      assert DominanceComparator.epsilon_dominates?(a, b)
    end

    test "returns true when A epsilon-dominates with small difference" do
      # A slightly better than B, must be > epsilon in at least one objective
      a = make_candidate("a", %{accuracy: 0.82, latency: 0.72})
      b = make_candidate("b", %{accuracy: 0.80, latency: 0.70})

      # With epsilon 0.01, difference of 0.02 satisfies a > b + epsilon
      assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.01)
    end

    test "returns false when difference is within epsilon" do
      # Very small differences
      a = make_candidate("a", %{accuracy: 0.805, latency: 0.705})
      b = make_candidate("b", %{accuracy: 0.800, latency: 0.700})

      # With epsilon 0.05, difference of 0.005 is not enough
      refute DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.05)
    end

    test "returns false for identical solutions" do
      a = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.7})

      refute DominanceComparator.epsilon_dominates?(a, b)
    end

    test "uses custom epsilon value" do
      a = make_candidate("a", %{accuracy: 1.0, latency: 0.9})
      b = make_candidate("b", %{accuracy: 0.85, latency: 0.75})

      # With epsilon 0.1, differences of 0.15 satisfy a > b + epsilon
      assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.1)
    end

    test "returns false when trade-off exists even with epsilon" do
      # A better in accuracy, B better in latency
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      refute DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.1)
    end

    test "handles four objectives with epsilon" do
      # Need difference > epsilon in at least one objective
      a = make_candidate("a", %{accuracy: 1.0, latency: 0.9, cost: 0.9, robustness: 0.95})
      b = make_candidate("b", %{accuracy: 0.85, latency: 0.75, cost: 0.75, robustness: 0.80})

      # Differences all >= 0.15, which is > 0.1
      assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.1)
    end

    test "returns false when one objective is worse by more than epsilon" do
      # A much better in accuracy, but worse in latency
      a = make_candidate("a", %{accuracy: 0.95, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.9})

      refute DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.01)
    end

    test "handles candidate with no normalized_objectives" do
      a = make_candidate("a", %{accuracy: 0.9})

      b = %Candidate{
        id: "b",
        prompt: "test",
        generation: 1,
        created_at: System.monotonic_time(:millisecond),
        normalized_objectives: nil
      }

      refute DominanceComparator.epsilon_dominates?(a, b)
      refute DominanceComparator.epsilon_dominates?(b, a)
    end

    test "epsilon allows for measurement noise" do
      # Simulate noisy measurements - values very close
      a = make_candidate("a", %{accuracy: 0.7520, latency: 0.6520})
      b = make_candidate("b", %{accuracy: 0.7500, latency: 0.6500})

      # With epsilon 0.01, difference of 0.002 is > 0.001 but < 0.01+0.001
      # Should dominate with small epsilon
      assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.001)

      # But not with larger epsilon since 0.002 is not > 0.01 + epsilon
      refute DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.01)
    end

    test "requires strict improvement in at least one objective" do
      # A better or equal in all, but need > epsilon in at least one
      a = make_candidate("a", %{accuracy: 0.8, latency: 0.70})
      b = make_candidate("b", %{accuracy: 0.8, latency: 0.69})

      # Difference of 0.01 in latency
      assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.001)
      refute DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.05)
    end
  end

  describe "integration: combined operations" do
    test "fast non-dominated sort followed by crowding distance" do
      candidates = [
        make_candidate("a", %{accuracy: 0.9, latency: 0.6}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.8}),
        make_candidate("c", %{accuracy: 0.7, latency: 0.5}),
        make_candidate("d", %{accuracy: 0.6, latency: 0.4})
      ]

      # First, classify into fronts
      fronts = DominanceComparator.fast_non_dominated_sort(candidates)

      # Then calculate crowding distance for front 1
      front_1 = fronts[1]
      distances = DominanceComparator.crowding_distance(front_1)

      # Should have distances for all front 1 members
      assert map_size(distances) == length(front_1)

      # All distances should be valid
      Enum.each(distances, fn {_id, dist} ->
        assert dist == :infinity or (is_float(dist) and dist >= 0.0)
      end)
    end

    test "dominance and epsilon-dominance consistency" do
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.6})

      # If A dominates B, A should also epsilon-dominate B
      if DominanceComparator.dominates?(a, b) do
        assert DominanceComparator.epsilon_dominates?(a, b, epsilon: 0.01)
      end
    end

    test "sorting preserves dominance relationships" do
      # Create population where we know dominance
      # Best
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.9})
      # Middle
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.7})
      # Worst
      c = make_candidate("c", %{accuracy: 0.5, latency: 0.5})

      fronts = DominanceComparator.fast_non_dominated_sort([a, b, c])

      # a should be in front 1
      front_1_ids = Enum.map(fronts[1], & &1.id)
      assert "a" in front_1_ids

      # c should be in a later front
      front_1_ids = Enum.map(fronts[1], & &1.id)
      refute "c" in front_1_ids
    end
  end
end
