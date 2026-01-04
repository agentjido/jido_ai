defmodule Jido.AI.Algorithms.HybridTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Hybrid

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  defmodule ValidateAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "validate",
      description: "Validates input"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :validated, true)}
    end
  end

  defmodule TransformAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "transform",
      description: "Transforms data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :transformed, true)}
    end
  end

  defmodule DoubleAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "double",
      description: "Doubles value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update(input, :value, 0, &(&1 * 2))}
    end
  end

  defmodule AddTenAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "add_ten",
      description: "Adds 10"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update(input, :value, 0, &(&1 + 10))}
    end
  end

  defmodule FetchAAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fetch_a",
      description: "Fetches A data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :a, "data_a")}
    end
  end

  defmodule FetchBAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fetch_b",
      description: "Fetches B data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :b, "data_b")}
    end
  end

  defmodule FetchCAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fetch_c",
      description: "Fetches C data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :c, "data_c")}
    end
  end

  defmodule ErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "error",
      description: "Always fails"

    @impl true
    def execute(_input, _context) do
      {:error, :intentional_error}
    end
  end

  defmodule FallbackAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fallback",
      description: "Fallback algorithm"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :fallback_used, true)}
    end
  end

  defmodule SecondFallbackAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "second_fallback",
      description: "Second fallback algorithm"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :second_fallback_used, true)}
    end
  end

  defmodule ConditionalAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "conditional",
      description: "Only executes for positive values"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :conditional, true)}
    end

    @impl true
    def can_execute?(input, _context) do
      Map.get(input, :value, 0) > 0
    end
  end

  # ============================================================================
  # Module Setup Tests
  # ============================================================================

  describe "module setup" do
    test "uses Base correctly" do
      assert function_exported?(Hybrid, :execute, 2)
      assert function_exported?(Hybrid, :can_execute?, 2)
      assert function_exported?(Hybrid, :metadata, 0)
    end

    test "metadata returns correct values" do
      metadata = Hybrid.metadata()

      assert metadata.name == "hybrid"
      assert metadata.description == "Combines sequential and parallel execution in stages"
    end
  end

  # ============================================================================
  # Basic Execute Tests
  # ============================================================================

  describe "execute/2" do
    test "returns input unchanged for empty stages" do
      input = %{value: 5}
      context = %{stages: []}

      assert {:ok, ^input} = Hybrid.execute(input, context)
    end

    test "returns input unchanged when stages key is missing" do
      input = %{value: 5}
      context = %{}

      assert {:ok, ^input} = Hybrid.execute(input, context)
    end

    test "processes single sequential stage" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm], mode: :sequential}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 5
      assert result.validated == true
    end

    test "processes single parallel stage" do
      input = %{}

      context = %{
        stages: [
          %{algorithms: [FetchAAlgorithm, FetchBAlgorithm], mode: :parallel}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.a == "data_a"
      assert result.b == "data_b"
    end
  end

  # ============================================================================
  # Sequential Stage Tests
  # ============================================================================

  describe "sequential stages" do
    test "executes algorithms in order" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [DoubleAlgorithm, AddTenAlgorithm], mode: :sequential}
        ]
      }

      # 5 -> double -> 10 -> add_ten -> 20
      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 20
    end

    test "chains output to next algorithm" do
      input = %{value: 3}

      context = %{
        stages: [
          %{algorithms: [DoubleAlgorithm, DoubleAlgorithm, DoubleAlgorithm], mode: :sequential}
        ]
      }

      # 3 -> 6 -> 12 -> 24
      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 24
    end

    test "halts on error" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [DoubleAlgorithm, ErrorAlgorithm, AddTenAlgorithm], mode: :sequential}
        ]
      }

      assert {:error, :intentional_error} = Hybrid.execute(input, context)
    end
  end

  # ============================================================================
  # Parallel Stage Tests
  # ============================================================================

  describe "parallel stages" do
    test "executes algorithms concurrently" do
      input = %{}

      context = %{
        stages: [
          %{algorithms: [FetchAAlgorithm, FetchBAlgorithm, FetchCAlgorithm], mode: :parallel}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.a == "data_a"
      assert result.b == "data_b"
      assert result.c == "data_c"
    end

    test "supports merge_strategy option" do
      input = %{}

      context = %{
        stages: [
          %{
            algorithms: [FetchAAlgorithm, FetchBAlgorithm],
            mode: :parallel,
            merge_strategy: :collect
          }
        ]
      }

      assert {:ok, results} = Hybrid.execute(input, context)
      assert is_list(results)
      assert length(results) == 2
    end

    test "supports error_mode option" do
      input = %{}

      context = %{
        stages: [
          %{
            algorithms: [FetchAAlgorithm, ErrorAlgorithm],
            mode: :parallel,
            error_mode: :ignore_errors
          }
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.a == "data_a"
    end
  end

  # ============================================================================
  # Multi-Stage Tests
  # ============================================================================

  describe "multi-stage execution" do
    test "processes stages in order" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm], mode: :sequential},
          %{algorithms: [DoubleAlgorithm], mode: :sequential},
          %{algorithms: [TransformAlgorithm], mode: :sequential}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      assert result.value == 10
      assert result.transformed == true
    end

    test "passes stage output to next stage input" do
      input = %{value: 2}

      context = %{
        stages: [
          %{algorithms: [DoubleAlgorithm], mode: :sequential},
          %{algorithms: [DoubleAlgorithm], mode: :sequential},
          %{algorithms: [AddTenAlgorithm], mode: :sequential}
        ]
      }

      # 2 -> stage1(double) -> 4 -> stage2(double) -> 8 -> stage3(add_ten) -> 18
      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 18
    end

    test "mixes sequential and parallel stages" do
      input = %{value: 5}

      context = %{
        stages: [
          # Stage 1: Validate sequentially
          %{algorithms: [ValidateAlgorithm], mode: :sequential},
          # Stage 2: Fetch in parallel
          %{algorithms: [FetchAAlgorithm, FetchBAlgorithm], mode: :parallel},
          # Stage 3: Transform sequentially
          %{algorithms: [TransformAlgorithm], mode: :sequential}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      assert result.a == "data_a"
      assert result.b == "data_b"
      assert result.transformed == true
    end

    test "halts on stage error" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm], mode: :sequential},
          %{algorithms: [ErrorAlgorithm], mode: :sequential},
          %{algorithms: [TransformAlgorithm], mode: :sequential}
        ]
      }

      assert {:error, :intentional_error} = Hybrid.execute(input, context)
    end
  end

  # ============================================================================
  # Stage Shorthand Tests
  # ============================================================================

  describe "stage shorthand" do
    test "single algorithm module is normalized to sequential stage" do
      input = %{value: 5}

      context = %{
        stages: [
          ValidateAlgorithm,
          DoubleAlgorithm
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      assert result.value == 10
    end

    test "map without mode defaults to sequential" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm, DoubleAlgorithm]}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      assert result.value == 10
    end
  end

  # ============================================================================
  # Fallback Tests
  # ============================================================================

  describe "fallback support" do
    test "uses fallback on primary failure" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ErrorAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ErrorAlgorithm => %{fallbacks: [FallbackAlgorithm]}
        }
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.fallback_used == true
    end

    test "tries multiple fallbacks in order" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ErrorAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ErrorAlgorithm => %{fallbacks: [ErrorAlgorithm, SecondFallbackAlgorithm]}
        }
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.second_fallback_used == true
    end

    test "returns error if all fallbacks fail" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ErrorAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ErrorAlgorithm => %{fallbacks: [ErrorAlgorithm]}
        }
      }

      assert {:error, :all_fallbacks_failed} = Hybrid.execute(input, context)
    end

    test "no fallback when primary succeeds" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ValidateAlgorithm => %{fallbacks: [FallbackAlgorithm]}
        }
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      refute Map.has_key?(result, :fallback_used)
    end
  end

  # ============================================================================
  # Can Execute Tests
  # ============================================================================

  describe "can_execute?/2" do
    test "returns true for empty stages" do
      assert Hybrid.can_execute?(%{}, %{stages: []})
    end

    test "returns true when all algorithms can execute" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm, ConditionalAlgorithm], mode: :sequential}
        ]
      }

      assert Hybrid.can_execute?(input, context)
    end

    test "returns false when any algorithm cannot execute" do
      input = %{value: -5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm, ConditionalAlgorithm], mode: :sequential}
        ]
      }

      refute Hybrid.can_execute?(input, context)
    end
  end

  # ============================================================================
  # Telemetry Tests
  # ============================================================================

  describe "telemetry" do
    setup do
      ref = make_ref()
      pid = self()
      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :ai, :algorithm, :hybrid, :start],
          [:jido, :ai, :algorithm, :hybrid, :stop],
          [:jido, :ai, :algorithm, :hybrid, :stage, :start],
          [:jido, :ai, :algorithm, :hybrid, :stage, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits start and stop events" do
      input = %{}
      context = %{stages: [ValidateAlgorithm]}

      {:ok, _} = Hybrid.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :hybrid, :start],
                      %{system_time: _, stage_count: 1}, %{}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :hybrid, :stop], %{duration: _},
                      %{stages_completed: 1}}
    end

    test "emits stage events" do
      input = %{}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm], mode: :sequential}
        ]
      }

      {:ok, _} = Hybrid.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :hybrid, :stage, :start], _,
                      %{stage_index: 0, mode: :sequential}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :hybrid, :stage, :stop], %{duration: _},
                      %{stage_index: 0, mode: :sequential}}
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "works with run_with_hooks" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ValidateAlgorithm, DoubleAlgorithm], mode: :sequential}
        ]
      }

      {:ok, result} = Hybrid.run_with_hooks(input, context)

      assert result.validated == true
      assert result.value == 10
    end

    test "complex workflow with all features" do
      input = %{value: 5}

      context = %{
        stages: [
          # Stage 1: Validate and transform
          ValidateAlgorithm,
          # Stage 2: Parallel fetch
          %{
            algorithms: [FetchAAlgorithm, FetchBAlgorithm],
            mode: :parallel,
            merge_strategy: :merge_maps
          },
          # Stage 3: Final processing
          %{algorithms: [DoubleAlgorithm, TransformAlgorithm], mode: :sequential}
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.validated == true
      assert result.a == "data_a"
      assert result.b == "data_b"
      assert result.value == 10
      assert result.transformed == true
    end
  end
end
