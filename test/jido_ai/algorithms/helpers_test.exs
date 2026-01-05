defmodule Jido.AI.Algorithms.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Helpers

  # ============================================================================
  # Deep Merge Tests
  # ============================================================================

  describe "deep_merge/2" do
    test "merges flat maps" do
      left = %{a: 1, b: 2}
      right = %{b: 3, c: 4}

      result = Helpers.deep_merge(left, right)

      assert result == %{a: 1, b: 3, c: 4}
    end

    test "deep merges nested maps" do
      left = %{a: %{b: 1, c: 2}}
      right = %{a: %{c: 3, d: 4}}

      result = Helpers.deep_merge(left, right)

      assert result == %{a: %{b: 1, c: 3, d: 4}}
    end

    test "handles deeply nested structures" do
      left = %{a: %{b: %{c: 1}}}
      right = %{a: %{b: %{d: 2}}}

      result = Helpers.deep_merge(left, right)

      assert result == %{a: %{b: %{c: 1, d: 2}}}
    end

    test "right value wins for non-map values" do
      left = %{a: 1, b: %{c: 2}}
      right = %{a: "replaced", b: "also replaced"}

      result = Helpers.deep_merge(left, right)

      assert result == %{a: "replaced", b: "also replaced"}
    end

    test "returns right when left is not a map" do
      result = Helpers.deep_merge("not a map", %{a: 1})
      assert result == %{a: 1}
    end
  end

  describe "deep_merge/3 with depth limit" do
    test "respects depth limit" do
      # Create a structure that would normally be deeply merged
      left = %{a: %{b: %{c: 1}}}
      right = %{a: %{b: %{d: 2}}}

      # With depth limit of 1, we can only merge 1 level deep
      # At level 0: merge top-level keys (a)
      # At level 1: merge a's value (which is a map), but we're at limit
      #            so right's %{b: %{d: 2}} replaces left's %{b: %{c: 1}}
      result = Helpers.deep_merge(left, right, 1)

      # At depth 1, the first level is merged but nested is replaced
      assert result == %{a: %{b: %{d: 2}}}
    end

    test "merges two levels with depth 2" do
      # 2 levels of nesting: a -> b (with values)
      left = %{a: %{b: 1, c: 2}}
      right = %{a: %{c: 3, d: 4}}

      # With depth 2, we can merge at level 0 and level 1
      result = Helpers.deep_merge(left, right, 2)

      assert result == %{a: %{b: 1, c: 3, d: 4}}
    end

    test "merges three levels with depth 3" do
      left = %{a: %{b: %{c: 1}}}
      right = %{a: %{b: %{d: 2}}}

      # With depth 3, we can merge all 3 levels
      result = Helpers.deep_merge(left, right, 3)

      assert result == %{a: %{b: %{c: 1, d: 2}}}
    end

    test "stops merging at depth 0" do
      left = %{a: %{b: 1}}
      right = %{a: %{c: 2}}

      result = Helpers.deep_merge(left, right, 0)

      # At depth 0, right completely replaces left
      assert result == %{a: %{c: 2}}
    end
  end

  # ============================================================================
  # Partition Results Tests
  # ============================================================================

  describe "partition_results/1" do
    test "partitions successes and errors" do
      results = [
        {:ok, 1},
        {:error, :fail1},
        {:ok, 2},
        {:error, :fail2},
        {:ok, 3}
      ]

      {successes, errors} = Helpers.partition_results(results)

      assert successes == [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      assert errors == [{:error, :fail1}, {:error, :fail2}]
    end

    test "handles all successes" do
      results = [{:ok, 1}, {:ok, 2}]
      {successes, errors} = Helpers.partition_results(results)

      assert successes == [{:ok, 1}, {:ok, 2}]
      assert errors == []
    end

    test "handles all errors" do
      results = [{:error, :a}, {:error, :b}]
      {successes, errors} = Helpers.partition_results(results)

      assert successes == []
      assert errors == [{:error, :a}, {:error, :b}]
    end

    test "handles empty list" do
      {successes, errors} = Helpers.partition_results([])

      assert successes == []
      assert errors == []
    end
  end

  # ============================================================================
  # Handle Results Tests
  # ============================================================================

  describe "handle_results/3 with :fail_fast" do
    test "returns merged results when all succeed" do
      results = [{:ok, %{a: 1}}, {:ok, %{b: 2}}]

      assert {:ok, %{a: 1, b: 2}} = Helpers.handle_results(results, :merge_maps, :fail_fast)
    end

    test "returns first error" do
      results = [{:ok, %{a: 1}}, {:error, :first}, {:error, :second}]

      assert {:error, :first} = Helpers.handle_results(results, :merge_maps, :fail_fast)
    end
  end

  describe "handle_results/3 with :collect_errors" do
    test "returns merged results when all succeed" do
      results = [{:ok, %{a: 1}}, {:ok, %{b: 2}}]

      assert {:ok, %{a: 1, b: 2}} = Helpers.handle_results(results, :merge_maps, :collect_errors)
    end

    test "returns all errors with successful results" do
      results = [{:ok, %{a: 1}}, {:error, :fail1}, {:ok, %{b: 2}}, {:error, :fail2}]

      assert {:error, result} = Helpers.handle_results(results, :merge_maps, :collect_errors)
      assert result.errors == [:fail1, :fail2]
      assert result.successful == [%{a: 1}, %{b: 2}]
    end

    test "returns only errors when all fail" do
      results = [{:error, :fail1}, {:error, :fail2}]

      assert {:error, result} = Helpers.handle_results(results, :merge_maps, :collect_errors)
      assert result.errors == [:fail1, :fail2]
      assert result.successful == []
    end
  end

  describe "handle_results/3 with :ignore_errors" do
    test "returns merged results ignoring errors" do
      results = [{:ok, %{a: 1}}, {:error, :fail}, {:ok, %{b: 2}}]

      assert {:ok, %{a: 1, b: 2}} = Helpers.handle_results(results, :merge_maps, :ignore_errors)
    end

    test "returns error when all fail" do
      results = [{:error, :fail1}, {:error, :fail2}]

      assert {:error, :all_failed} = Helpers.handle_results(results, :merge_maps, :ignore_errors)
    end
  end

  # ============================================================================
  # Merge Successes Tests
  # ============================================================================

  describe "merge_successes/2" do
    test "merges maps with :merge_maps strategy" do
      successes = [{:ok, %{a: 1}}, {:ok, %{b: 2}}]

      assert {:ok, %{a: 1, b: 2}} = Helpers.merge_successes(successes, :merge_maps)
    end

    test "collects results with :collect strategy" do
      successes = [{:ok, %{a: 1}}, {:ok, %{b: 2}}]

      assert {:ok, [%{a: 1}, %{b: 2}]} = Helpers.merge_successes(successes, :collect)
    end

    test "applies custom merge function" do
      successes = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      merge_fn = fn results -> Enum.sum(results) end

      assert {:ok, 6} = Helpers.merge_successes(successes, merge_fn)
    end
  end

  # ============================================================================
  # Valid Algorithm Tests
  # ============================================================================

  describe "valid_algorithm?/1" do
    defmodule ValidAlgo do
      def execute(_input, _context), do: {:ok, %{}}
    end

    defmodule InvalidAlgo do
      def not_execute(_input), do: :nope
    end

    test "returns true for module with execute/2" do
      assert Helpers.valid_algorithm?(ValidAlgo)
    end

    test "returns false for module without execute/2" do
      refute Helpers.valid_algorithm?(InvalidAlgo)
    end

    test "returns false for non-atom" do
      refute Helpers.valid_algorithm?("not a module")
      refute Helpers.valid_algorithm?(123)
      refute Helpers.valid_algorithm?(%{})
    end
  end
end
