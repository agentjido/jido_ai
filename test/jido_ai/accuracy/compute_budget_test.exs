defmodule Jido.AI.Accuracy.ComputeBudgetTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.ComputeBudget

  doctest ComputeBudget

  describe "new/1" do
    test "creates budget with valid attributes" do
      assert {:ok, budget} = ComputeBudget.new(%{num_candidates: 5})
      assert budget.num_candidates == 5
      assert budget.use_prm == false
      assert budget.use_search == false
    end

    test "creates budget with all attributes" do
      assert {:ok, budget} =
               ComputeBudget.new(%{
                 num_candidates: 10,
                 use_prm: true,
                 use_search: true,
                 max_refinements: 2,
                 search_iterations: 50,
                 prm_threshold: 0.7,
                 metadata: %{"key" => "value"}
               })

      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert budget.max_refinements == 2
      assert budget.search_iterations == 50
      assert budget.prm_threshold == 0.7
      assert budget.metadata == %{"key" => "value"}
    end

    test "returns error for invalid num_candidates" do
      assert {:error, :invalid_num_candidates} = ComputeBudget.new(%{num_candidates: 0})
      assert {:error, :invalid_num_candidates} = ComputeBudget.new(%{num_candidates: -1})
      assert {:error, :invalid_num_candidates} = ComputeBudget.new(%{num_candidates: "invalid"})
    end

    test "defaults search_iterations when not provided but search enabled" do
      assert {:ok, budget} = ComputeBudget.new(%{num_candidates: 5, use_search: true})
      assert budget.search_iterations == 50
    end

    test "respects provided search_iterations" do
      assert {:ok, budget} =
               ComputeBudget.new(%{num_candidates: 5, use_search: true, search_iterations: 100})

      assert budget.search_iterations == 100
    end
  end

  describe "new!/1" do
    test "returns budget with valid attributes" do
      budget = ComputeBudget.new!(%{num_candidates: 5})
      assert budget.num_candidates == 5
    end

    test "raises on invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid ComputeBudget/, fn ->
        ComputeBudget.new!(%{num_candidates: -1})
      end
    end
  end

  describe "easy/0" do
    test "returns preset budget for easy tasks" do
      budget = ComputeBudget.easy()
      assert budget.num_candidates == 3
      assert budget.use_prm == false
      assert budget.use_search == false
      assert budget.max_refinements == 0
    end

    test "has correct cost" do
      budget = ComputeBudget.easy()
      assert budget.cost == 3.0
    end
  end

  describe "medium/0" do
    test "returns preset budget for medium tasks" do
      budget = ComputeBudget.medium()
      assert budget.num_candidates == 5
      assert budget.use_prm == true
      assert budget.use_search == false
      assert budget.max_refinements == 1
    end

    test "has correct cost" do
      budget = ComputeBudget.medium()
      # 5 (candidates) + 2.5 (PRM) + 1 (refinement) = 8.5
      assert_in_delta budget.cost, 8.5, 0.01
    end

    test "has default prm_threshold" do
      budget = ComputeBudget.medium()
      assert budget.prm_threshold == 0.5
    end
  end

  describe "hard/0" do
    test "returns preset budget for hard tasks" do
      budget = ComputeBudget.hard()
      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert budget.max_refinements == 2
      assert budget.search_iterations == 50
    end

    test "has correct cost" do
      budget = ComputeBudget.hard()
      # 10 (candidates) + 5 (PRM) + 0.5 (search) + 2 (refinements) = 17.5
      assert_in_delta budget.cost, 17.5, 0.01
    end
  end

  describe "for_level/1" do
    test "returns easy budget for :easy" do
      budget = ComputeBudget.for_level(:easy)
      assert budget.num_candidates == 3
      assert budget.use_prm == false
    end

    test "returns medium budget for :medium" do
      budget = ComputeBudget.for_level(:medium)
      assert budget.num_candidates == 5
      assert budget.use_prm == true
    end

    test "returns hard budget for :hard" do
      budget = ComputeBudget.for_level(:hard)
      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
    end
  end

  describe "cost/1" do
    test "returns computed cost" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_prm: true})
      assert ComputeBudget.cost(budget) == budget.cost
    end

    test "calculates cost correctly for basic allocation" do
      budget = ComputeBudget.new!(%{num_candidates: 5})
      assert budget.cost == 5.0
    end

    test "calculates cost correctly with PRM" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_prm: true})
      assert_in_delta budget.cost, 7.5, 0.01
    end

    test "calculates cost correctly with search" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_search: true, search_iterations: 100})
      # 5 + 0 + 1 + 0 = 6
      assert_in_delta budget.cost, 6.0, 0.01
    end

    test "calculates cost correctly with all options" do
      budget =
        ComputeBudget.new!(%{
          num_candidates: 10,
          use_prm: true,
          use_search: true,
          search_iterations: 50,
          max_refinements: 2
        })

      # 10 (candidates) + 5 (PRM) + 0.5 (search) + 2 (refinements) = 17.5
      assert_in_delta budget.cost, 17.5, 0.01
    end
  end

  describe "num_candidates/1" do
    test "returns num_candidates from budget" do
      budget = ComputeBudget.new!(%{num_candidates: 7})
      assert ComputeBudget.num_candidates(budget) == 7
    end
  end

  describe "use_prm?/1" do
    test "returns true when PRM enabled" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_prm: true})
      assert ComputeBudget.use_prm?(budget) == true
    end

    test "returns false when PRM disabled" do
      budget = ComputeBudget.new!(%{num_candidates: 5})
      assert ComputeBudget.use_prm?(budget) == false
    end
  end

  describe "use_search?/1" do
    test "returns true when search enabled" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_search: true})
      assert ComputeBudget.use_search?(budget) == true
    end

    test "returns false when search disabled" do
      budget = ComputeBudget.new!(%{num_candidates: 5})
      assert ComputeBudget.use_search?(budget) == false
    end
  end

  describe "to_map/1" do
    test "converts budget to map" do
      budget = ComputeBudget.medium()
      map = ComputeBudget.to_map(budget)

      assert map["num_candidates"] == 5
      assert map["use_prm"] == true
      assert map["use_search"] == false
      assert map["max_refinements"] == 1
      assert map["prm_threshold"] == 0.5
      assert is_number(map["cost"])
      assert map["metadata"] == %{}
    end
  end

  describe "from_map/1" do
    test "creates budget from map" do
      map = %{
        "num_candidates" => 7,
        "use_prm" => true,
        "use_search" => false,
        "max_refinements" => 1
      }

      assert {:ok, budget} = ComputeBudget.from_map(map)
      assert budget.num_candidates == 7
      assert budget.use_prm == true
      assert budget.use_search == false
      assert budget.max_refinements == 1
    end

    test "handles nil values" do
      map = %{
        "num_candidates" => 5,
        "use_prm" => nil,
        "use_search" => nil,
        "search_iterations" => nil
      }

      assert {:ok, budget} = ComputeBudget.from_map(map)
      assert budget.num_candidates == 5
      assert budget.use_prm == false
      assert budget.use_search == false
      assert budget.search_iterations == nil
    end

    test "handles metadata" do
      map = %{
        "num_candidates" => 5,
        "metadata" => %{"key" => "value"}
      }

      assert {:ok, budget} = ComputeBudget.from_map(map)
      assert budget.metadata == %{"key" => "value"}
    end

    test "returns error for invalid num_candidates" do
      map = %{"num_candidates" => 0}
      assert {:error, :invalid_num_candidates} = ComputeBudget.from_map(map)
    end

    test "round-trip: to_map then from_map" do
      original = ComputeBudget.hard()
      map = ComputeBudget.to_map(original)
      assert {:ok, restored} = ComputeBudget.from_map(map)

      assert restored.num_candidates == original.num_candidates
      assert restored.use_prm == original.use_prm
      assert restored.use_search == original.use_search
      assert restored.max_refinements == original.max_refinements
      assert_in_delta restored.cost, original.cost, 0.01
    end
  end

  describe "cost calculation edge cases" do
    test "handles zero refinements" do
      budget = ComputeBudget.new!(%{num_candidates: 5, max_refinements: 0})
      assert_in_delta budget.cost, 5.0, 0.01
    end

    test "handles large search iterations" do
      budget = ComputeBudget.new!(%{num_candidates: 5, use_search: true, search_iterations: 1000})
      # 5 + 10 = 15
      assert_in_delta budget.cost, 15.0, 0.01
    end

    test "handles many refinements" do
      budget = ComputeBudget.new!(%{num_candidates: 5, max_refinements: 10})
      # 5 + 10 = 15
      assert_in_delta budget.cost, 15.0, 0.01
    end
  end
end
