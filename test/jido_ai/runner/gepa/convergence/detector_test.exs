defmodule Jido.AI.Runner.GEPA.Convergence.DetectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Convergence.Detector

  describe "new/1" do
    test "creates detector with default configuration" do
      detector = Detector.new()

      assert detector.plateau_detector != nil
      assert detector.diversity_monitor != nil
      assert detector.hypervolume_tracker != nil
      assert detector.budget_manager != nil
      assert detector.current_generation == 0
    end

    test "accepts custom configuration for all detectors" do
      detector =
        Detector.new(
          plateau_opts: [patience: 10],
          diversity_opts: [critical_threshold: 0.10],
          hypervolume_opts: [patience: 8],
          budget_opts: [max_evaluations: 500]
        )

      assert detector.plateau_detector.patience == 10
      assert detector.diversity_monitor.critical_threshold == 0.10
      assert detector.hypervolume_tracker.patience == 8
      assert detector.budget_manager.max_evaluations == 500
    end

    test "stores configuration in config field" do
      detector = Detector.new(custom_param: :value)

      assert detector.config[:custom_param] == :value
    end
  end

  describe "update/2" do
    test "updates all detectors when all metrics provided" do
      detector = Detector.new()

      metrics = %{
        fitness_record: %{
          generation: 1,
          best_fitness: 0.8,
          mean_fitness: 0.75,
          median_fitness: 0.73,
          std_dev: 0.05
        },
        diversity_metrics: %{
          generation: 1,
          pairwise_diversity: 0.65,
          diversity_level: :healthy,
          convergence_risk: 0.2
        },
        hypervolume: 0.75,
        consumption: [evaluations: 50, cost: 1.25]
      }

      detector = Detector.update(detector, metrics)

      assert detector.current_generation == 1
      assert length(detector.plateau_detector.fitness_history) == 1
      assert length(detector.diversity_monitor.diversity_history) == 1
      assert length(detector.hypervolume_tracker.hypervolume_history) == 1
      assert length(detector.budget_manager.consumption_history) == 1
    end

    test "updates only provided metrics" do
      detector = Detector.new()

      metrics = %{
        fitness_record: %{
          generation: 1,
          best_fitness: 0.8,
          mean_fitness: 0.75,
          median_fitness: 0.73,
          std_dev: 0.05
        }
      }

      detector = Detector.update(detector, metrics)

      assert length(detector.plateau_detector.fitness_history) == 1
      assert Enum.empty?(detector.diversity_monitor.diversity_history)
      assert Enum.empty?(detector.hypervolume_tracker.hypervolume_history)
    end

    test "increments generation counter" do
      detector = Detector.new()

      detector =
        detector
        |> Detector.update(%{
          fitness_record: %{
            generation: 1,
            best_fitness: 0.8,
            mean_fitness: 0.75,
            median_fitness: 0.73,
            std_dev: 0.05
          }
        })
        |> Detector.update(%{
          fitness_record: %{
            generation: 2,
            best_fitness: 0.82,
            mean_fitness: 0.76,
            median_fitness: 0.74,
            std_dev: 0.04
          }
        })
        |> Detector.update(%{
          fitness_record: %{
            generation: 3,
            best_fitness: 0.84,
            mean_fitness: 0.77,
            median_fitness: 0.75,
            std_dev: 0.03
          }
        })

      assert detector.current_generation == 3
    end

    test "handles explicit generation number in metrics" do
      detector = Detector.new()

      metrics = %{
        generation: 42,
        fitness_record: %{
          generation: 42,
          best_fitness: 0.8,
          mean_fitness: 0.75,
          median_fitness: 0.73,
          std_dev: 0.05
        }
      }

      detector = Detector.update(detector, metrics)

      assert detector.current_generation == 42
    end
  end

  describe "get_status/1" do
    test "returns status with no convergence initially" do
      detector = Detector.new()
      status = Detector.get_status(detector)

      refute status.converged
      assert status.status_level == :running
      assert status.reason == nil
      refute status.should_stop
    end

    test "includes all individual detector statuses" do
      detector = Detector.new()
      status = Detector.get_status(detector)

      refute status.plateau_detected
      refute status.diversity_collapsed
      refute status.hypervolume_saturated
      refute status.budget_exhausted
    end

    test "includes metadata with generation info" do
      detector = Detector.new()

      detector =
        Detector.update(detector, %{
          generation: 5,
          fitness_record: %{
            generation: 5,
            best_fitness: 0.8,
            mean_fitness: 0.75,
            median_fitness: 0.73,
            std_dev: 0.05
          }
        })

      status = Detector.get_status(detector)

      assert status.metadata.generation == 5
    end
  end

  describe "convergence detection - fitness plateau" do
    test "detects convergence when fitness plateaus" do
      detector = Detector.new(plateau_opts: [patience: 2, window_size: 2])

      # Create stagnant fitness
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5,
              mean_fitness: 0.45,
              median_fitness: 0.43,
              std_dev: 0.05
            }
          })
        end)

      status = Detector.get_status(detector)

      assert status.converged
      assert status.plateau_detected
      assert status.reason == :fitness_plateau
      assert status.should_stop
    end

    test "does not detect convergence with improving fitness" do
      detector = Detector.new()

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5 + gen * 0.05,
              mean_fitness: 0.45 + gen * 0.05,
              median_fitness: 0.43 + gen * 0.05,
              std_dev: 0.05
            }
          })
        end)

      status = Detector.get_status(detector)

      refute status.converged
      refute status.plateau_detected
    end
  end

  describe "convergence detection - diversity collapse" do
    test "detects convergence when diversity collapses" do
      detector = Detector.new(diversity_opts: [critical_threshold: 0.15, patience: 2])

      # Create collapsing diversity
      detector =
        Enum.reduce(1..6, detector, fn gen, acc ->
          Detector.update(acc, %{
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.10,
              diversity_level: :critical,
              convergence_risk: 0.9
            }
          })
        end)

      status = Detector.get_status(detector)

      assert status.converged
      assert status.diversity_collapsed
      assert status.reason == :diversity_collapse
      assert status.should_stop
    end

    test "does not detect convergence with healthy diversity" do
      detector = Detector.new()

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.65,
              diversity_level: :healthy,
              convergence_risk: 0.1
            }
          })
        end)

      status = Detector.get_status(detector)

      refute status.converged
      refute status.diversity_collapsed
    end
  end

  describe "convergence detection - hypervolume saturation" do
    test "detects convergence when hypervolume saturates" do
      detector = Detector.new(hypervolume_opts: [patience: 2])

      # Create saturated hypervolume
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          Detector.update(acc, %{hypervolume: 0.75})
        end)

      status = Detector.get_status(detector)

      assert status.converged
      assert status.hypervolume_saturated
      assert status.reason == :hypervolume_saturation
      assert status.should_stop
    end

    test "does not detect convergence with growing hypervolume" do
      detector = Detector.new()

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{hypervolume: 0.5 + gen * 0.05})
        end)

      status = Detector.get_status(detector)

      refute status.converged
      refute status.hypervolume_saturated
    end
  end

  describe "convergence detection - budget exhaustion" do
    test "detects convergence when budget exhausted" do
      detector = Detector.new(budget_opts: [max_evaluations: 100])

      # Exhaust budget
      detector = Detector.update(detector, %{consumption: [evaluations: 100]})

      status = Detector.get_status(detector)

      assert status.converged
      assert status.budget_exhausted
      assert status.reason == :budget_exhausted
      assert status.should_stop
    end

    test "does not detect convergence with remaining budget" do
      detector = Detector.new(budget_opts: [max_evaluations: 1000])

      detector =
        Enum.reduce(1..10, detector, fn _gen, acc ->
          Detector.update(acc, %{consumption: [evaluations: 50]})
        end)

      status = Detector.get_status(detector)

      refute status.converged
      refute status.budget_exhausted
    end
  end

  describe "convergence detection - multiple criteria" do
    test "converges when any criterion triggers" do
      detector =
        Detector.new(
          plateau_opts: [patience: 2, window_size: 2],
          budget_opts: [max_evaluations: 1000]
        )

      # Trigger plateau but not budget
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5,
              mean_fitness: 0.45,
              median_fitness: 0.43,
              std_dev: 0.05
            },
            consumption: [evaluations: 50]
          })
        end)

      status = Detector.get_status(detector)

      assert status.converged
      assert status.plateau_detected
      refute status.budget_exhausted
      assert status.reason == :fitness_plateau
    end

    test "prioritizes budget exhaustion in reason" do
      detector =
        Detector.new(
          plateau_opts: [patience: 2, window_size: 2],
          budget_opts: [max_evaluations: 100]
        )

      # Trigger both plateau and budget
      detector =
        Enum.reduce(1..8, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5,
              mean_fitness: 0.45,
              median_fitness: 0.43,
              std_dev: 0.05
            },
            consumption: [evaluations: 15]
          })
        end)

      status = Detector.get_status(detector)

      assert status.converged
      assert status.plateau_detected
      assert status.budget_exhausted
      # Budget has priority
      assert status.reason == :budget_exhausted
    end

    test "does not converge when no criteria triggered" do
      detector = Detector.new(budget_opts: [max_evaluations: 1000])

      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5 + gen * 0.05,
              mean_fitness: 0.45 + gen * 0.05,
              median_fitness: 0.43 + gen * 0.05,
              std_dev: 0.05
            },
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.65,
              diversity_level: :healthy,
              convergence_risk: 0.1
            },
            hypervolume: 0.5 + gen * 0.05,
            consumption: [evaluations: 50]
          })
        end)

      status = Detector.get_status(detector)

      refute status.converged
      refute status.plateau_detected
      refute status.diversity_collapsed
      refute status.hypervolume_saturated
      refute status.budget_exhausted
    end
  end

  describe "warning generation" do
    test "generates warning when diversity in warning zone" do
      detector = Detector.new(diversity_opts: [warning_threshold: 0.30, critical_threshold: 0.15])

      detector =
        Detector.update(detector, %{
          diversity_metrics: %{
            generation: 1,
            # Below warning, above critical
            pairwise_diversity: 0.25,
            diversity_level: :low,
            convergence_risk: 0.5
          }
        })

      status = Detector.get_status(detector)

      assert "Diversity below warning threshold" in status.warnings
    end

    test "generates warning when approaching plateau" do
      detector = Detector.new(plateau_opts: [patience: 5, window_size: 2])

      # Get halfway through patience
      detector =
        Enum.reduce(1..6, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5,
              mean_fitness: 0.45,
              median_fitness: 0.43,
              std_dev: 0.05
            }
          })
        end)

      status = Detector.get_status(detector)

      assert Enum.any?(status.warnings, &String.contains?(&1, "Approaching fitness plateau"))
    end

    test "generates warning when budget 80% consumed" do
      detector = Detector.new(budget_opts: [max_evaluations: 100])

      detector = Detector.update(detector, %{consumption: [evaluations: 85]})

      status = Detector.get_status(detector)

      assert Enum.any?(status.warnings, &String.contains?(&1, "Budget 80% consumed"))
    end

    test "does not generate warnings when all metrics healthy" do
      detector = Detector.new(budget_opts: [max_evaluations: 1000])

      detector =
        Detector.update(detector, %{
          fitness_record: %{
            generation: 1,
            best_fitness: 0.8,
            mean_fitness: 0.75,
            median_fitness: 0.73,
            std_dev: 0.05
          },
          diversity_metrics: %{
            generation: 1,
            pairwise_diversity: 0.65,
            diversity_level: :healthy,
            convergence_risk: 0.1
          },
          hypervolume: 0.75,
          consumption: [evaluations: 50]
        })

      status = Detector.get_status(detector)

      assert status.warnings == []
    end
  end

  describe "converged?/1" do
    test "returns false for new detector" do
      detector = Detector.new()
      refute Detector.converged?(detector)
    end

    test "returns true when any detector triggers" do
      detector = Detector.new(budget_opts: [max_evaluations: 100])
      detector = Detector.update(detector, %{consumption: [evaluations: 100]})

      assert Detector.converged?(detector)
    end
  end

  describe "reset/1" do
    test "resets all detectors" do
      detector = Detector.new(budget_opts: [max_evaluations: 100])

      detector =
        Enum.reduce(1..5, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5,
              mean_fitness: 0.45,
              median_fitness: 0.43,
              std_dev: 0.05
            },
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.65,
              diversity_level: :healthy,
              convergence_risk: 0.1
            },
            hypervolume: 0.75,
            consumption: [evaluations: 20]
          })
        end)

      assert detector.current_generation == 5

      detector = Detector.reset(detector)

      assert detector.current_generation == 0
      assert detector.plateau_detector.fitness_history == []
      assert detector.diversity_monitor.diversity_history == []
      assert detector.hypervolume_tracker.hypervolume_history == []
      assert detector.budget_manager.consumption_history == []
    end

    test "preserves configuration after reset" do
      detector =
        Detector.new(
          plateau_opts: [patience: 10],
          budget_opts: [max_evaluations: 500]
        )

      detector = Detector.update(detector, %{consumption: [evaluations: 100]})
      detector = Detector.reset(detector)

      assert detector.plateau_detector.patience == 10
      assert detector.budget_manager.max_evaluations == 500
    end
  end

  describe "integration scenarios" do
    test "full optimization cycle until convergence" do
      detector =
        Detector.new(
          plateau_opts: [patience: 3, window_size: 2],
          # Increased budget to avoid exhaustion before plateau
          budget_opts: [max_evaluations: 1000]
        )

      # Initial improving phase
      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5 + gen * 0.03,
              mean_fitness: 0.45 + gen * 0.03,
              median_fitness: 0.43 + gen * 0.03,
              std_dev: 0.05
            },
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.70 - gen * 0.02,
              diversity_level: :healthy,
              convergence_risk: gen * 0.05
            },
            hypervolume: 0.4 + gen * 0.04,
            consumption: [evaluations: 30, cost: 0.5]
          })
        end)

      refute Detector.converged?(detector)

      # Plateau phase
      detector =
        Enum.reduce(11..20, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.80,
              mean_fitness: 0.75,
              median_fitness: 0.73,
              std_dev: 0.05
            },
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: 0.50,
              diversity_level: :healthy,
              convergence_risk: 0.5
            },
            hypervolume: 0.75,
            consumption: [evaluations: 30, cost: 0.5]
          })
        end)

      assert Detector.converged?(detector)

      status = Detector.get_status(detector)
      assert status.reason == :fitness_plateau
      assert status.plateau_detected
    end

    test "early budget exhaustion stops before plateau" do
      detector =
        Detector.new(
          plateau_opts: [patience: 10],
          budget_opts: [max_evaluations: 150]
        )

      # Improving fitness but running out of budget
      detector =
        Enum.reduce(1..5, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5 + gen * 0.05,
              mean_fitness: 0.45 + gen * 0.05,
              median_fitness: 0.43 + gen * 0.05,
              std_dev: 0.05
            },
            consumption: [evaluations: 30]
          })
        end)

      assert Detector.converged?(detector)

      status = Detector.get_status(detector)
      assert status.reason == :budget_exhausted
      refute status.plateau_detected
    end

    test "diversity collapse triggers early termination" do
      detector =
        Detector.new(
          diversity_opts: [critical_threshold: 0.15, patience: 2],
          plateau_opts: [patience: 10]
        )

      # Fitness still improving but diversity collapsing
      detector =
        Enum.reduce(1..10, detector, fn gen, acc ->
          Detector.update(acc, %{
            fitness_record: %{
              generation: gen,
              best_fitness: 0.5 + gen * 0.05,
              mean_fitness: 0.45 + gen * 0.05,
              median_fitness: 0.43 + gen * 0.05,
              std_dev: 0.05
            },
            diversity_metrics: %{
              generation: gen,
              pairwise_diversity: max(0.05, 0.50 - gen * 0.05),
              diversity_level: if(gen > 7, do: :critical, else: :moderate),
              convergence_risk: min(0.9, gen * 0.1)
            }
          })
        end)

      assert Detector.converged?(detector)

      status = Detector.get_status(detector)
      assert status.reason == :diversity_collapse
      refute status.plateau_detected
    end
  end
end
