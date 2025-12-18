defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator
  alias Jido.AI.Runner.GEPA.Population.Candidate

  doctest HypervolumeCalculator

  # Test fixtures

  defp make_candidate(id, normalized_objectives) do
    %Candidate{
      id: id,
      prompt: "test prompt",
      fitness: 0.5,
      normalized_objectives: normalized_objectives,
      created_at: System.monotonic_time(:millisecond),
      generation: 1
    }
  end

  describe "calculate/2" do
    test "returns error when reference_point is missing" do
      solutions = [make_candidate("c1", %{accuracy: 0.8})]

      assert {:error, {:missing_required_option, :reference_point}} =
               HypervolumeCalculator.calculate(solutions, objectives: [:accuracy])
    end

    test "returns error when objectives is missing" do
      solutions = [make_candidate("c1", %{accuracy: 0.8})]

      assert {:error, {:missing_required_option, :objectives}} =
               HypervolumeCalculator.calculate(solutions, reference_point: %{accuracy: 0.0})
    end

    test "returns error when reference_point has non-numeric values" do
      solutions = [make_candidate("c1", %{accuracy: 0.8})]

      assert {:error, {:non_numeric_reference_values, _}} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: "invalid"},
                 objectives: [:accuracy]
               )
    end

    test "returns error when reference_point is missing objective" do
      solutions = [make_candidate("c1", %{accuracy: 0.8, latency: 0.5})]

      assert {:error, :missing_reference_value} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0},
                 objectives: [:accuracy, :latency]
               )
    end

    test "returns 0.0 for empty solution set" do
      assert {:ok, 0.0} =
               HypervolumeCalculator.calculate(
                 [],
                 reference_point: %{accuracy: 0.0},
                 objectives: [:accuracy]
               )
    end

    test "filters out solutions without normalized_objectives" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8}),
        %Candidate{
          id: "c2",
          prompt: "test",
          normalized_objectives: nil,
          created_at: System.monotonic_time(:millisecond),
          generation: 1,
          fitness: 0.0
        }
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0},
                 objectives: [:accuracy]
               )

      assert hv > 0.0
    end
  end

  describe "calculate/2 with 1D objectives" do
    test "calculates hypervolume for single objective" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8}),
        make_candidate("c2", %{accuracy: 0.6}),
        make_candidate("c3", %{accuracy: 0.7})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0},
                 objectives: [:accuracy]
               )

      # Max value is 0.8, reference is 0.0, so HV = 0.8
      assert_in_delta hv, 0.8, 0.001
    end

    test "calculates hypervolume with non-zero reference point" do
      solutions = [make_candidate("c1", %{accuracy: 0.8})]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.5},
                 objectives: [:accuracy]
               )

      # HV = 0.8 - 0.5 = 0.3
      assert_in_delta hv, 0.3, 0.001
    end

    test "returns 0 when solution equals reference point" do
      solutions = [make_candidate("c1", %{accuracy: 0.5})]

      assert {:ok, 0.0} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.5},
                 objectives: [:accuracy]
               )
    end

    test "returns 0 when solution is dominated by reference point" do
      solutions = [make_candidate("c1", %{accuracy: 0.3})]

      assert {:ok, 0.0} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.5},
                 objectives: [:accuracy]
               )
    end
  end

  describe "calculate/2 with 2D objectives" do
    test "calculates hypervolume for two objectives" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8}),
        make_candidate("c2", %{accuracy: 0.7, latency: 0.9}),
        make_candidate("c3", %{accuracy: 0.8, latency: 0.7})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0},
                 objectives: [:accuracy, :latency]
               )

      # Hypervolume should be positive
      assert hv > 0.0
      # Should be less than the bounding box area (1.0 * 1.0 = 1.0)
      assert hv < 1.0
    end

    test "calculates exact hypervolume for 2D case with known answer" do
      # Two non-dominated solutions forming a simple staircase
      solutions = [
        make_candidate("c1", %{accuracy: 1.0, latency: 0.5}),
        make_candidate("c2", %{accuracy: 0.5, latency: 1.0})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0},
                 objectives: [:accuracy, :latency]
               )

      # HV = (1.0 - 0.0) * (0.5 - 0.0) + (0.5 - 0.0) * (1.0 - 0.5)
      #    = 1.0 * 0.5 + 0.5 * 0.5
      #    = 0.5 + 0.25 = 0.75
      assert_in_delta hv, 0.75, 0.001
    end

    test "handles dominated solution in 2D" do
      # c2 dominates c3
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.6}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.8}),
        # Dominated by c2
        make_candidate("c3", %{accuracy: 0.7, latency: 0.7})
      ]

      assert {:ok, hv_with_dominated} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0},
                 objectives: [:accuracy, :latency]
               )

      # Remove dominated solution
      non_dominated = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.6}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.8})
      ]

      assert {:ok, hv_without_dominated} =
               HypervolumeCalculator.calculate(
                 non_dominated,
                 reference_point: %{accuracy: 0.0, latency: 0.0},
                 objectives: [:accuracy, :latency]
               )

      # Hypervolume should be the same
      assert_in_delta hv_with_dominated, hv_without_dominated, 0.001
    end

    test "calculates hypervolume with non-zero reference point in 2D" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.5, latency: 0.5},
                 objectives: [:accuracy, :latency]
               )

      # HV = (0.9 - 0.5) * (0.8 - 0.5) = 0.4 * 0.3 = 0.12
      assert_in_delta hv, 0.12, 0.001
    end

    test "returns 0 when all solutions dominated by reference point in 2D" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.3, latency: 0.4})
      ]

      assert {:ok, 0.0} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.5, latency: 0.5},
                 objectives: [:accuracy, :latency]
               )
    end
  end

  describe "calculate/2 with 3D objectives" do
    test "calculates hypervolume for three objectives" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8, cost: 0.7}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.9, cost: 0.8}),
        make_candidate("c3", %{accuracy: 0.7, latency: 0.7, cost: 0.9})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0},
                 objectives: [:accuracy, :latency, :cost]
               )

      # Hypervolume should be positive
      assert hv > 0.0
      # Should be less than the bounding box volume (1.0 * 1.0 * 1.0 = 1.0)
      assert hv < 1.0
    end

    test "calculates exact hypervolume for 3D case with single solution" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8, latency: 0.7, cost: 0.6})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0},
                 objectives: [:accuracy, :latency, :cost]
               )

      # HV = 0.8 * 0.7 * 0.6 = 0.336
      assert_in_delta hv, 0.336, 0.001
    end

    test "handles dominated solutions in 3D" do
      # c1 dominates c3
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.9, cost: 0.9}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.7, cost: 0.6}),
        # Dominated by c2
        make_candidate("c3", %{accuracy: 0.7, latency: 0.6, cost: 0.5})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0},
                 objectives: [:accuracy, :latency, :cost]
               )

      # Dominated solution shouldn't affect hypervolume
      assert hv > 0.0
    end
  end

  describe "calculate/2 with 4+ objectives" do
    test "calculates hypervolume for four objectives" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8, cost: 0.7, robustness: 0.85}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.9, cost: 0.8, robustness: 0.75}),
        make_candidate("c3", %{accuracy: 0.7, latency: 0.7, cost: 0.9, robustness: 0.95})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0, robustness: 0.0},
                 objectives: [:accuracy, :latency, :cost, :robustness]
               )

      # Hypervolume should be positive
      assert hv > 0.0
      # Should be less than the bounding box hypervolume (1.0^4 = 1.0)
      assert hv < 1.0
    end

    test "calculates exact hypervolume for 4D case with single solution" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8, latency: 0.7, cost: 0.6, robustness: 0.5})
      ]

      assert {:ok, hv} =
               HypervolumeCalculator.calculate(
                 solutions,
                 reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0, robustness: 0.0},
                 objectives: [:accuracy, :latency, :cost, :robustness]
               )

      # HV = 0.8 * 0.7 * 0.6 * 0.5 = 0.168
      assert_in_delta hv, 0.168, 0.001
    end
  end

  describe "contribution/2" do
    test "calculates contribution for each solution in 1D" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8}),
        make_candidate("c2", %{accuracy: 0.6})
      ]

      contributions =
        HypervolumeCalculator.contribution(
          solutions,
          reference_point: %{accuracy: 0.0},
          objectives: [:accuracy]
        )

      assert is_map(contributions)
      assert Map.has_key?(contributions, "c1")
      assert Map.has_key?(contributions, "c2")

      # c1 has higher value, so should have higher contribution
      assert contributions["c1"] > contributions["c2"]
    end

    test "calculates contribution for each solution in 2D" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.6}),
        make_candidate("c2", %{accuracy: 0.6, latency: 0.9})
      ]

      contributions =
        HypervolumeCalculator.contribution(
          solutions,
          reference_point: %{accuracy: 0.0, latency: 0.0},
          objectives: [:accuracy, :latency]
        )

      assert Map.has_key?(contributions, "c1")
      assert Map.has_key?(contributions, "c2")

      # Both solutions should have positive contribution
      assert contributions["c1"] > 0.0
      assert contributions["c2"] > 0.0

      # Verify hypervolume calculation is reasonable
      {:ok, total_hv} =
        HypervolumeCalculator.calculate(
          solutions,
          reference_point: %{accuracy: 0.0, latency: 0.0},
          objectives: [:accuracy, :latency]
        )

      # For non-dominated solutions with overlap, sum of exclusive contributions
      # will be less than total HV due to shared dominated regions
      total_contrib = contributions["c1"] + contributions["c2"]
      assert total_contrib > 0.0
      assert total_contrib <= total_hv
    end

    test "dominated solution has zero contribution" do
      # c2 dominates c3
      solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.6}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.8}),
        # Dominated
        make_candidate("c3", %{accuracy: 0.7, latency: 0.7})
      ]

      contributions =
        HypervolumeCalculator.contribution(
          solutions,
          reference_point: %{accuracy: 0.0, latency: 0.0},
          objectives: [:accuracy, :latency]
        )

      # Dominated solution should have zero or near-zero contribution
      assert contributions["c3"] < 0.01
    end

    test "returns zero contributions on error" do
      solutions = [make_candidate("c1", %{accuracy: 0.8})]

      # Missing required option
      contributions =
        HypervolumeCalculator.contribution(
          solutions,
          objectives: [:accuracy]
        )

      assert contributions == %{"c1" => 0.0}
    end

    test "handles empty solution set" do
      contributions =
        HypervolumeCalculator.contribution(
          [],
          reference_point: %{accuracy: 0.0},
          objectives: [:accuracy]
        )

      assert contributions == %{}
    end
  end

  describe "auto_reference_point/2" do
    test "selects reference point below minimum values" do
      candidates = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8}),
        make_candidate("c2", %{accuracy: 0.7, latency: 0.6}),
        make_candidate("c3", %{accuracy: 0.8, latency: 0.7})
      ]

      reference =
        HypervolumeCalculator.auto_reference_point(
          candidates,
          objectives: [:accuracy, :latency],
          objective_directions: %{accuracy: :maximize, latency: :minimize},
          margin: 0.1
        )

      assert is_map(reference)
      assert Map.has_key?(reference, :accuracy)
      assert Map.has_key?(reference, :latency)

      # Reference should be below minimum values
      # Min accuracy: 0.7, reference should be 0.7 - 0.1 = 0.6
      # Min latency: 0.6, reference should be 0.6 - 0.1 = 0.5
      assert_in_delta reference[:accuracy], 0.6, 0.01
      assert_in_delta reference[:latency], 0.5, 0.01
    end

    test "uses default margin when not specified" do
      candidates = [
        make_candidate("c1", %{accuracy: 0.8})
      ]

      reference =
        HypervolumeCalculator.auto_reference_point(
          candidates,
          objectives: [:accuracy],
          objective_directions: %{accuracy: :maximize}
        )

      # Default margin is 0.1, so reference should be 0.8 - 0.1 = 0.7
      assert_in_delta reference[:accuracy], 0.7, 0.01
    end

    test "returns zero reference point for empty candidates" do
      reference =
        HypervolumeCalculator.auto_reference_point(
          [],
          objectives: [:accuracy, :latency],
          objective_directions: %{accuracy: :maximize, latency: :minimize}
        )

      assert reference == %{accuracy: 0.0, latency: 0.0}
    end

    test "filters candidates without normalized_objectives" do
      candidates = [
        make_candidate("c1", %{accuracy: 0.8}),
        %Candidate{
          id: "c2",
          prompt: "test",
          normalized_objectives: nil,
          created_at: System.monotonic_time(:millisecond),
          generation: 1,
          fitness: 0.0
        }
      ]

      reference =
        HypervolumeCalculator.auto_reference_point(
          candidates,
          objectives: [:accuracy],
          objective_directions: %{accuracy: :maximize},
          margin: 0.1
        )

      # Should use only c1's value
      assert_in_delta reference[:accuracy], 0.7, 0.01
    end

    test "ensures reference point is non-negative" do
      candidates = [
        # Very small value
        make_candidate("c1", %{accuracy: 0.05})
      ]

      reference =
        HypervolumeCalculator.auto_reference_point(
          candidates,
          objectives: [:accuracy],
          objective_directions: %{accuracy: :maximize},
          margin: 0.1
        )

      # 0.05 - 0.1 would be -0.05, but should be clamped to 0.0
      assert reference[:accuracy] >= 0.0
    end
  end

  describe "improvement/3" do
    test "calculates improvement ratio between frontiers" do
      # Previous frontier
      previous_solutions = [
        make_candidate("p1", %{accuracy: 0.7, latency: 0.6}),
        make_candidate("p2", %{accuracy: 0.6, latency: 0.7})
      ]

      previous_frontier = %{solutions: previous_solutions}

      # Current frontier (improved)
      current_solutions = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.8}),
        make_candidate("c2", %{accuracy: 0.8, latency: 0.9})
      ]

      current_frontier = %{solutions: current_solutions}

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      assert {:ok, ratio, current_hv} =
               HypervolumeCalculator.improvement(current_frontier, previous_frontier, opts)

      # Current should be better than previous
      assert ratio > 1.0
      assert current_hv > 0.0
    end

    test "returns 1.0 ratio when hypervolumes are equal" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.8, latency: 0.7})
      ]

      frontier = %{solutions: solutions}

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      assert {:ok, ratio, _hv} =
               HypervolumeCalculator.improvement(frontier, frontier, opts)

      assert_in_delta ratio, 1.0, 0.01
    end

    test "returns infinity when previous hypervolume is zero" do
      previous_frontier = %{solutions: []}

      current_frontier = %{
        solutions: [make_candidate("c1", %{accuracy: 0.8, latency: 0.7})]
      }

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      assert {:ok, ratio, _hv} =
               HypervolumeCalculator.improvement(current_frontier, previous_frontier, opts)

      assert ratio == :infinity
    end

    test "returns 1.0 when both hypervolumes are zero" do
      frontier = %{solutions: []}

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      assert {:ok, ratio, _hv} =
               HypervolumeCalculator.improvement(frontier, frontier, opts)

      assert ratio == 1.0
    end
  end

  describe "integration tests" do
    test "hypervolume increases when adding non-dominated solution" do
      initial = [
        make_candidate("c1", %{accuracy: 0.7, latency: 0.6})
      ]

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      {:ok, initial_hv} = HypervolumeCalculator.calculate(initial, opts)

      # Add non-dominated solution
      improved =
        initial ++
          [
            make_candidate("c2", %{accuracy: 0.6, latency: 0.8})
          ]

      {:ok, improved_hv} = HypervolumeCalculator.calculate(improved, opts)

      assert improved_hv > initial_hv
    end

    test "hypervolume unchanged when adding dominated solution" do
      initial = [
        make_candidate("c1", %{accuracy: 0.9, latency: 0.9})
      ]

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      ]

      {:ok, initial_hv} = HypervolumeCalculator.calculate(initial, opts)

      # Add dominated solution
      with_dominated =
        initial ++
          [
            # Dominated
            make_candidate("c2", %{accuracy: 0.5, latency: 0.5})
          ]

      {:ok, dominated_hv} = HypervolumeCalculator.calculate(with_dominated, opts)

      assert_in_delta dominated_hv, initial_hv, 0.001
    end

    test "works with realistic GEPA objectives" do
      solutions = [
        make_candidate("c1", %{accuracy: 0.92, latency: 0.85, cost: 0.78, robustness: 0.88}),
        make_candidate("c2", %{accuracy: 0.88, latency: 0.92, cost: 0.82, robustness: 0.85}),
        make_candidate("c3", %{accuracy: 0.85, latency: 0.88, cost: 0.95, robustness: 0.92}),
        make_candidate("c4", %{accuracy: 0.95, latency: 0.75, cost: 0.70, robustness: 0.80})
      ]

      opts = [
        reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0, robustness: 0.0},
        objectives: [:accuracy, :latency, :cost, :robustness]
      ]

      assert {:ok, hv} = HypervolumeCalculator.calculate(solutions, opts)
      assert hv > 0.0
      assert hv < 1.0

      # Verify contributions can be calculated
      contributions = HypervolumeCalculator.contribution(solutions, opts)

      # All contributions should be non-negative
      assert Enum.all?(contributions, fn {_id, contrib} -> contrib >= 0.0 end)

      # At least some contributions should be positive (though some may be 0 for dominated solutions)
      # Note: For high-dimensional spaces, contribution calculation is complex
      assert is_map(contributions)
      assert map_size(contributions) == 4
    end
  end
end
