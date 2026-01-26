defmodule Jido.AI.GEPA.SelectionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.{PromptVariant, Selection}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_variant(accuracy, token_cost, opts \\ []) do
    id = Keyword.get(opts, :id, "pv_#{:rand.uniform(100_000)}")
    latency = Keyword.get(opts, :latency_ms)

    %PromptVariant{
      id: id,
      template: "test",
      generation: 0,
      parents: [],
      accuracy: accuracy,
      token_cost: token_cost,
      latency_ms: latency,
      metadata: %{}
    }
  end

  defp default_objectives do
    [{:accuracy, :maximize}, {:token_cost, :minimize}]
  end

  # ============================================================================
  # dominates?/3
  # ============================================================================

  describe "dominates?/3" do
    test "returns true when A is better on all objectives" do
      a = create_variant(0.9, 100)
      b = create_variant(0.8, 150)

      assert Selection.dominates?(a, b, default_objectives())
    end

    test "returns true when A equals on one and better on another" do
      a = create_variant(0.9, 100)
      b = create_variant(0.9, 150)

      assert Selection.dominates?(a, b, default_objectives())
    end

    test "returns false when neither dominates (trade-off)" do
      # Better accuracy, worse cost
      a = create_variant(0.9, 200)
      # Worse accuracy, better cost
      b = create_variant(0.8, 100)

      refute Selection.dominates?(a, b, default_objectives())
      refute Selection.dominates?(b, a, default_objectives())
    end

    test "returns false when A is worse on all objectives" do
      a = create_variant(0.7, 200)
      b = create_variant(0.9, 100)

      refute Selection.dominates?(a, b, default_objectives())
    end

    test "returns false when variants are equal" do
      a = create_variant(0.9, 100)
      b = create_variant(0.9, 100)

      refute Selection.dominates?(a, b, default_objectives())
    end

    test "handles nil values as equal" do
      a = create_variant(0.9, nil)
      b = create_variant(0.8, 100)

      # nil cost is treated as equal to any value
      # A has better accuracy (0.9 > 0.8) and equal cost (nil == 100)
      # So A dominates B
      assert Selection.dominates?(a, b, default_objectives())

      # When both have nil, neither dominates if accuracy is equal
      c = create_variant(0.9, nil)
      d = create_variant(0.9, nil)
      refute Selection.dominates?(c, d, default_objectives())
    end

    test "works with minimize-only objectives" do
      objectives = [{:token_cost, :minimize}, {:latency_ms, :minimize}]

      a = create_variant(nil, 100, latency_ms: 50)
      b = create_variant(nil, 150, latency_ms: 100)

      assert Selection.dominates?(a, b, objectives)
    end

    test "works with maximize-only objectives" do
      objectives = [{:accuracy, :maximize}]

      a = create_variant(0.9, 100)
      b = create_variant(0.8, 50)

      assert Selection.dominates?(a, b, objectives)
    end
  end

  # ============================================================================
  # pareto_front/2
  # ============================================================================

  describe "pareto_front/2" do
    test "returns single variant when only one" do
      v = create_variant(0.9, 100)
      assert Selection.pareto_front([v]) == [v]
    end

    test "returns both when neither dominates" do
      # High accuracy, high cost
      a = create_variant(0.9, 200, id: "a")
      # Low accuracy, low cost
      b = create_variant(0.7, 100, id: "b")

      front = Selection.pareto_front([a, b])
      assert length(front) == 2
      assert a in front
      assert b in front
    end

    test "excludes dominated variants" do
      # Dominates c
      a = create_variant(0.9, 100, id: "a")
      # Different trade-off
      b = create_variant(0.7, 80, id: "b")
      # Dominated by a
      c = create_variant(0.8, 150, id: "c")

      front = Selection.pareto_front([a, b, c])
      assert length(front) == 2
      assert a in front
      assert b in front
      refute c in front
    end

    test "returns empty list for empty input" do
      assert Selection.pareto_front([]) == []
    end

    test "filters out unevaluated variants" do
      a = create_variant(0.9, 100, id: "a")
      b = %PromptVariant{id: "b", template: "test", accuracy: nil, token_cost: nil}

      front = Selection.pareto_front([a, b])
      assert front == [a]
    end

    test "handles many variants" do
      variants =
        for i <- 1..20 do
          # Create a range of trade-offs
          # 0.525 to 1.0
          acc = 0.5 + i / 40
          # 60 to 250
          cost = 50 + i * 10
          create_variant(acc, cost, id: "v#{i}")
        end

      front = Selection.pareto_front(variants)
      # Should have multiple variants in the front (the best trade-offs)
      assert front != []
      assert length(front) <= length(variants)
    end

    test "uses default objectives when not specified" do
      a = create_variant(0.9, 100)
      front = Selection.pareto_front([a])
      assert front == [a]
    end

    test "works with custom objectives" do
      objectives = [{:latency_ms, :minimize}]

      a = create_variant(0.5, 100, id: "a", latency_ms: 50)
      b = create_variant(0.9, 50, id: "b", latency_ms: 100)

      front = Selection.pareto_front([a, b], objectives)
      # Only latency matters, a is better
      assert front == [a]
    end
  end

  # ============================================================================
  # select_survivors/3
  # ============================================================================

  describe "select_survivors/3" do
    test "returns requested count" do
      variants =
        for i <- 1..10 do
          create_variant(0.5 + i * 0.04, 100 + i * 10, id: "v#{i}")
        end

      survivors = Selection.select_survivors(variants, 5)
      assert length(survivors) == 5
    end

    test "returns all when count exceeds available" do
      variants = [
        create_variant(0.9, 100, id: "a"),
        create_variant(0.8, 80, id: "b")
      ]

      survivors = Selection.select_survivors(variants, 10)
      assert length(survivors) == 2
    end

    test "returns empty list when count is 0" do
      variants = [create_variant(0.9, 100)]
      assert Selection.select_survivors(variants, 0) == []
    end

    test "returns empty list for empty input" do
      assert Selection.select_survivors([], 5) == []
    end

    test "prioritizes Pareto front with default strategy" do
      # Create clear Pareto front
      front_a = create_variant(0.95, 100, id: "front_a")
      front_b = create_variant(0.7, 50, id: "front_b")
      dominated = create_variant(0.8, 150, id: "dominated")

      survivors = Selection.select_survivors([front_a, front_b, dominated], 2)

      assert front_a in survivors
      assert front_b in survivors
    end

    test "includes non-front when needed" do
      front = create_variant(0.95, 100, id: "front")
      other = create_variant(0.8, 150, id: "other")

      survivors = Selection.select_survivors([front, other], 2)

      assert length(survivors) == 2
      assert front in survivors
    end

    test "filters unevaluated variants" do
      evaluated = create_variant(0.9, 100, id: "eval")
      unevaluated = %PromptVariant{id: "uneval", template: "test", accuracy: nil, token_cost: nil}

      survivors = Selection.select_survivors([evaluated, unevaluated], 2)

      assert survivors == [evaluated]
    end

    test "works with :nsga2 strategy" do
      variants =
        for i <- 1..10 do
          create_variant(0.5 + i * 0.04, 100 + i * 10, id: "v#{i}")
        end

      survivors = Selection.select_survivors(variants, 5, strategy: :nsga2)
      assert length(survivors) == 5
    end

    test "works with :weighted strategy" do
      high_acc = create_variant(0.95, 200, id: "high_acc")
      low_cost = create_variant(0.7, 50, id: "low_cost")
      balanced = create_variant(0.85, 100, id: "balanced")

      # With equal weights, balanced might score well
      survivors =
        Selection.select_survivors(
          [high_acc, low_cost, balanced],
          2,
          strategy: :weighted
        )

      assert length(survivors) == 2
    end

    test "respects custom weights in weighted strategy" do
      high_acc = create_variant(0.99, 500, id: "high_acc")
      low_cost = create_variant(0.5, 10, id: "low_cost")

      # Strongly weight accuracy
      survivors =
        Selection.select_survivors(
          [high_acc, low_cost],
          1,
          strategy: :weighted,
          weights: %{accuracy: 0.99, token_cost: 0.01}
        )

      assert hd(survivors).id == "high_acc"
    end
  end

  # ============================================================================
  # crowding_distance/2
  # ============================================================================

  describe "crowding_distance/2" do
    test "returns infinity for single variant" do
      v = create_variant(0.9, 100)
      distances = Selection.crowding_distance([v])
      assert Map.get(distances, v.id) == :infinity
    end

    test "returns infinity for two variants" do
      a = create_variant(0.9, 100, id: "a")
      b = create_variant(0.8, 50, id: "b")

      distances = Selection.crowding_distance([a, b])
      assert Map.get(distances, "a") == :infinity
      assert Map.get(distances, "b") == :infinity
    end

    test "boundary variants get infinity" do
      # Create a line of variants
      # Best accuracy
      v1 = create_variant(0.9, 100, id: "v1")
      # Middle
      v2 = create_variant(0.8, 80, id: "v2")
      # Best cost
      v3 = create_variant(0.7, 60, id: "v3")

      distances = Selection.crowding_distance([v1, v2, v3])

      # Boundaries should be infinity
      assert Map.get(distances, "v1") == :infinity
      assert Map.get(distances, "v3") == :infinity
      # Middle should have finite distance
      assert is_number(Map.get(distances, "v2"))
    end

    test "middle variants have finite distance" do
      variants =
        for i <- 1..5 do
          create_variant(0.5 + i * 0.1, 100 + i * 20, id: "v#{i}")
        end

      distances = Selection.crowding_distance(variants)

      # Check middle variants have finite values
      middle_distances =
        distances
        |> Map.values()
        |> Enum.filter(&is_number/1)

      refute Enum.empty?(middle_distances)
    end
  end

  # ============================================================================
  # default_objectives/0
  # ============================================================================

  describe "default_objectives/0" do
    test "returns accuracy maximize and token_cost minimize" do
      objectives = Selection.default_objectives()

      assert {:accuracy, :maximize} in objectives
      assert {:token_cost, :minimize} in objectives
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles variants with same metrics" do
      a = create_variant(0.9, 100, id: "a")
      b = create_variant(0.9, 100, id: "b")
      c = create_variant(0.9, 100, id: "c")

      front = Selection.pareto_front([a, b, c])
      # All are equal, none dominates, all in front
      assert length(front) == 3
    end

    test "handles zero values" do
      a = create_variant(0.0, 0, id: "a")
      b = create_variant(0.5, 100, id: "b")

      front = Selection.pareto_front([a, b])
      # b dominates a on accuracy, a dominates b on cost
      # Neither dominates - both in front
      assert length(front) == 2
    end

    test "handles three objectives" do
      objectives = [
        {:accuracy, :maximize},
        {:token_cost, :minimize},
        {:latency_ms, :minimize}
      ]

      a = create_variant(0.9, 100, id: "a", latency_ms: 50)
      b = create_variant(0.8, 80, id: "b", latency_ms: 100)
      c = create_variant(0.7, 120, id: "c", latency_ms: 30)

      front = Selection.pareto_front([a, b, c], objectives)
      # All have different trade-offs
      assert front != []
    end

    test "select_survivors maintains order stability" do
      # Create variants that should have deterministic selection
      variants =
        for i <- 1..5 do
          create_variant(1.0 - i * 0.1, 100 + i * 10, id: "v#{i}")
        end

      survivors1 = Selection.select_survivors(variants, 3)
      survivors2 = Selection.select_survivors(variants, 3)

      assert survivors1 == survivors2
    end
  end
end
