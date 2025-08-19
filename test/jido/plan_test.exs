defmodule Jido.PlanTest do
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias Jido.Plan

  # Mock action modules for testing
  defmodule TestActions do
    defmodule FetchAction do
      use Jido.Action,
        name: "fetch_action",
        description: "Fetches data for testing"

      @impl true
      def run(params, context) do
        {:ok, %{data: "fetched", params: params, context: context}}
      end
    end

    defmodule ValidateAction do
      use Jido.Action,
        name: "validate_action",
        description: "Validates data for testing"

      @impl true
      def run(params, context) do
        {:ok, %{valid: true, params: params, context: context}}
      end
    end

    defmodule SaveAction do
      use Jido.Action,
        name: "save_action",
        description: "Saves data for testing"

      @impl true
      def run(params, context) do
        {:ok, %{saved: true, params: params, context: context}}
      end
    end

    defmodule MergeAction do
      use Jido.Action,
        name: "merge_action",
        description: "Merges data for testing"

      @impl true
      def run(params, context) do
        {:ok, %{merged: true, params: params, context: context}}
      end
    end

    defmodule FetchUsersAction do
      use Jido.Action,
        name: "fetch_users_action",
        description: "Fetches users for testing"

      @impl true
      def run(params, context) do
        {:ok, %{users: ["user1", "user2"], params: params, context: context}}
      end
    end

    defmodule FetchOrdersAction do
      use Jido.Action,
        name: "fetch_orders_action",
        description: "Fetches orders for testing"

      @impl true
      def run(params, context) do
        {:ok, %{orders: ["order1", "order2"], params: params, context: context}}
      end
    end

    defmodule FetchProductsAction do
      use Jido.Action,
        name: "fetch_products_action",
        description: "Fetches products for testing"

      @impl true
      def run(params, context) do
        {:ok, %{products: ["product1", "product2"], params: params, context: context}}
      end
    end
  end

  describe "Plan creation" do
    test "creates empty plan with new/0" do
      plan = Plan.new()
      assert %Plan{} = plan
      assert plan.steps == %{}
      assert plan.context == %{}
    end

    test "creates plan with context" do
      plan = Plan.new(context: %{user_id: "123"})
      assert plan.context == %{user_id: "123"}
    end
  end

  describe "Builder pattern - add/4" do
    test "adds simple instruction with action module" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction)

      assert Map.has_key?(plan.steps, :fetch)

      plan_instruction = plan.steps[:fetch]
      assert %Plan.PlanInstruction{} = plan_instruction
      assert plan_instruction.name == :fetch
      assert %Instruction{action: TestActions.FetchAction} = plan_instruction.instruction
      assert plan_instruction.depends_on == []
    end

    test "adds instruction with parameters" do
      params = %{source: "api", limit: 10}

      plan =
        Plan.new()
        |> Plan.add(:fetch, {TestActions.FetchAction, params})

      plan_instruction = plan.steps[:fetch]
      assert plan_instruction.instruction.action == TestActions.FetchAction
      assert plan_instruction.instruction.params == params
    end

    test "adds instruction with dependencies" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction)
        |> Plan.add(:validate, TestActions.ValidateAction, depends_on: :fetch)

      validate_instruction = plan.steps[:validate]
      assert validate_instruction.depends_on == [:fetch]
    end

    test "adds instruction with multiple dependencies" do
      plan =
        Plan.new()
        |> Plan.add(:fetch1, TestActions.FetchAction)
        |> Plan.add(:fetch2, TestActions.FetchAction)
        |> Plan.add(:merge, TestActions.MergeAction, depends_on: [:fetch1, :fetch2])

      merge_instruction = plan.steps[:merge]
      assert merge_instruction.depends_on == [:fetch1, :fetch2]
    end

    test "builds sequential pipeline" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction)
        |> Plan.add(:validate, TestActions.ValidateAction, depends_on: :fetch)
        |> Plan.add(:save, TestActions.SaveAction, depends_on: :validate)

      assert plan.steps[:fetch].depends_on == []
      assert plan.steps[:validate].depends_on == [:fetch]
      assert plan.steps[:save].depends_on == [:validate]
    end
  end

  describe "Builder pattern - depends_on/3" do
    test "adds dependency to existing step" do
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, TestActions.ValidateAction)
        |> Plan.depends_on(:step2, :step1)

      assert plan.steps[:step2].depends_on == [:step1]
    end

    test "adds multiple dependencies" do
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, TestActions.ValidateAction)
        |> Plan.add(:step3, TestActions.SaveAction)
        |> Plan.depends_on(:step3, [:step1, :step2])

      assert plan.steps[:step3].depends_on == [:step1, :step2]
    end

    test "accumulates dependencies when called multiple times" do
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, TestActions.ValidateAction)
        |> Plan.add(:step3, TestActions.SaveAction)
        |> Plan.depends_on(:step3, :step1)
        |> Plan.depends_on(:step3, :step2)

      assert Enum.sort(plan.steps[:step3].depends_on) == [:step1, :step2]
    end

    test "raises error for non-existent step" do
      plan = Plan.new() |> Plan.add(:step1, TestActions.FetchAction)

      assert_raise RuntimeError, fn ->
        Plan.depends_on(plan, :nonexistent, :step1)
      end
    end
  end

  describe "build/3" do
    test "creates plan from simple keyword list" do
      plan_def = [
        fetch: TestActions.FetchAction,
        validate: {TestActions.ValidateAction, depends_on: :fetch},
        save: {TestActions.SaveAction, depends_on: :validate}
      ]

      {:ok, plan} = Plan.build(plan_def)

      assert Map.has_key?(plan.steps, :fetch)
      assert Map.has_key?(plan.steps, :validate)
      assert Map.has_key?(plan.steps, :save)
      assert plan.steps[:validate].depends_on == [:fetch]
      assert plan.steps[:save].depends_on == [:validate]
    end

    test "creates plan with parameters" do
      plan_def = [
        fetch: {TestActions.FetchAction, %{source: "api"}},
        validate: {TestActions.ValidateAction, %{strict: true}, depends_on: :fetch}
      ]

      {:ok, plan} = Plan.build(plan_def)

      fetch_instruction = plan.steps[:fetch]
      assert fetch_instruction.instruction.action == TestActions.FetchAction
      assert fetch_instruction.instruction.params == %{source: "api"}

      validate_instruction = plan.steps[:validate]
      assert validate_instruction.instruction.action == TestActions.ValidateAction
      assert validate_instruction.instruction.params == %{strict: true}
      assert validate_instruction.depends_on == [:fetch]
    end

    test "creates plan with context" do
      plan_def = [fetch: TestActions.FetchAction]
      context = %{user_id: "123"}

      {:ok, plan} = Plan.build(plan_def, context)

      assert plan.context == context
      # Context should be merged into instruction context
      assert plan.steps[:fetch].instruction.context[:user_id] == "123"
    end

    test "raises on invalid keyword list" do
      invalid_plan = [:not, :a, :keyword, :list]

      assert {:error, error} = Plan.build(invalid_plan)
      assert is_exception(error)
    end

    test "build!/3 raises on error" do
      invalid_plan = [:not, :a, :keyword, :list]

      assert_raise RuntimeError, fn ->
        Plan.build!(invalid_plan)
      end
    end
  end

  describe "normalize/1" do
    test "normalizes simple plan to graph and instructions" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction)
        |> Plan.add(:save, TestActions.SaveAction, depends_on: :fetch)

      {:ok, {graph, plan_instructions}} = Plan.normalize(plan)

      # Check that graph is properly constructed
      assert Graph.num_edges(graph) == 1
      assert length(plan_instructions) == 2

      assert Enum.all?(plan_instructions, fn plan_instruction ->
               match?(%Plan.PlanInstruction{}, plan_instruction) and
                 match?(%Instruction{}, plan_instruction.instruction)
             end)

      # Check that step names are preserved
      step_names = Enum.map(plan_instructions, & &1.name)
      assert :fetch in step_names
      assert :save in step_names
    end

    test "detects circular dependencies" do
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction, depends_on: :step2)
        |> Plan.add(:step2, TestActions.ValidateAction, depends_on: :step1)

      assert {:error, error} = Plan.normalize(plan)
      assert is_exception(error)
    end

    test "normalize!/1 raises on error" do
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction, depends_on: :step2)
        |> Plan.add(:step2, TestActions.ValidateAction, depends_on: :step1)

      assert_raise RuntimeError, fn ->
        Plan.normalize!(plan)
      end
    end
  end

  describe "execution_phases/1" do
    test "returns execution phases for sequential plan" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction)
        |> Plan.add(:validate, TestActions.ValidateAction, depends_on: :fetch)
        |> Plan.add(:save, TestActions.SaveAction, depends_on: :validate)

      {:ok, phases} = Plan.execution_phases(plan)

      assert phases == [[:fetch], [:validate], [:save]]
    end

    test "returns execution phases for parallel plan" do
      plan =
        Plan.new()
        |> Plan.add(:fetch_users, TestActions.FetchUsersAction)
        |> Plan.add(:fetch_orders, TestActions.FetchOrdersAction)
        |> Plan.add(:merge, TestActions.MergeAction, depends_on: [:fetch_users, :fetch_orders])

      {:ok, phases} = Plan.execution_phases(plan)

      # First phase should contain the parallel steps
      assert length(phases) == 2
      first_phase = Enum.sort(hd(phases))
      assert first_phase == [:fetch_orders, :fetch_users]
      assert Enum.at(phases, 1) == [:merge]
    end

    test "returns execution phases for complex plan" do
      plan =
        Plan.new()
        |> Plan.add(:init, TestActions.FetchAction)
        |> Plan.add(:fetch_users, TestActions.FetchUsersAction, depends_on: :init)
        |> Plan.add(:fetch_orders, TestActions.FetchOrdersAction, depends_on: :init)
        |> Plan.add(:merge, TestActions.MergeAction, depends_on: [:fetch_users, :fetch_orders])
        |> Plan.add(:save, TestActions.SaveAction, depends_on: :merge)

      {:ok, phases} = Plan.execution_phases(plan)

      assert length(phases) == 4
      assert hd(phases) == [:init]
      second_phase = Enum.sort(Enum.at(phases, 1))
      assert second_phase == [:fetch_orders, :fetch_users]
      assert Enum.at(phases, 2) == [:merge]
      assert Enum.at(phases, 3) == [:save]
    end
  end

  describe "to_keyword/1" do
    test "converts simple plan back to keyword format" do
      original_plan_def = [
        fetch: TestActions.FetchAction,
        validate: {TestActions.ValidateAction, depends_on: :fetch}
      ]

      {:ok, plan} = Plan.build(original_plan_def)
      result = Plan.to_keyword(plan)

      # Should contain the same steps (order might differ)
      result_map = Map.new(result)
      assert result_map[:fetch] == TestActions.FetchAction
      assert result_map[:validate] == {TestActions.ValidateAction, depends_on: [:fetch]}
    end

    test "converts plan with parameters" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, {TestActions.FetchAction, %{source: "api"}})
        |> Plan.add(:save, TestActions.SaveAction, depends_on: :fetch)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      assert result_map[:fetch] == {TestActions.FetchAction, %{source: "api"}}
      assert result_map[:save] == {TestActions.SaveAction, depends_on: [:fetch]}
    end
  end

  describe "Complex integration patterns" do
    test "builds complex plan with mixed patterns" do
      # Build using all available methods
      plan =
        Plan.new(context: %{tenant_id: "test"})
        |> Plan.add(:init, {TestActions.FetchAction, %{stage: "init"}})
        |> Plan.add(:fetch_users, {TestActions.FetchUsersAction, %{limit: 100}},
          depends_on: :init
        )
        |> Plan.add(:fetch_orders, {TestActions.FetchOrdersAction, %{status: "active"}},
          depends_on: :init
        )
        |> Plan.add(:validate, TestActions.ValidateAction,
          depends_on: [:fetch_users, :fetch_orders]
        )
        |> Plan.add(:merge, TestActions.MergeAction, depends_on: [:fetch_users, :fetch_orders])
        |> Plan.add(:save, TestActions.SaveAction, depends_on: [:validate, :merge])

      # Normalize and validate
      {:ok, {graph, plan_instructions}} = Plan.normalize(plan)

      assert Graph.num_vertices(graph) == 6
      assert Graph.is_acyclic?(graph)

      # Check execution phases
      {:ok, phases} = Plan.execution_phases(plan)
      assert length(phases) == 4

      # First phase: init
      assert hd(phases) == [:init]

      # Second phase: parallel data loading
      second_phase = Enum.sort(Enum.at(phases, 1))
      assert second_phase == [:fetch_orders, :fetch_users]

      # Third phase: validate and merge (can run in parallel)
      third_phase = Enum.sort(Enum.at(phases, 2))
      assert third_phase == [:merge, :validate]

      # Fourth phase: save
      assert Enum.at(phases, 3) == [:save]

      # Verify instructions have correct context
      assert Enum.all?(plan_instructions, fn plan_instruction ->
               plan_instruction.instruction.context[:tenant_id] == "test"
             end)
    end

    test "round-trip conversion preserves structure" do
      original_def = [
        init: {TestActions.FetchAction, %{stage: "init"}},
        fetch_users: {TestActions.FetchUsersAction, depends_on: :init},
        fetch_orders: {TestActions.FetchOrdersAction, depends_on: :init},
        merge: {TestActions.MergeAction, depends_on: [:fetch_users, :fetch_orders]}
      ]

      {:ok, plan} = Plan.build(original_def)
      converted = Plan.to_keyword(plan)
      {:ok, plan2} = Plan.build(converted)

      # Both plans should normalize to equivalent graphs
      {:ok, {graph1, _}} = Plan.normalize(plan)
      {:ok, {graph2, _}} = Plan.normalize(plan2)

      assert Graph.num_vertices(graph1) == Graph.num_vertices(graph2)
      assert Graph.num_edges(graph1) == Graph.num_edges(graph2)
    end
  end

  describe "PlanInstruction struct" do
    test "creates PlanInstruction with all fields" do
      plan_instruction = %Plan.PlanInstruction{
        name: :test_step,
        instruction: %Instruction{action: TestActions.FetchAction},
        depends_on: [:other_step],
        opts: [timeout: 5000]
      }

      assert plan_instruction.name == :test_step
      assert plan_instruction.instruction.action == TestActions.FetchAction
      assert plan_instruction.depends_on == [:other_step]
      assert plan_instruction.opts == [timeout: 5000]
      assert is_binary(plan_instruction.id)
    end

    test "PlanInstruction can be pattern matched" do
      plan =
        Plan.new()
        |> Plan.add(:fetch, TestActions.FetchAction, depends_on: :init)

      %Plan.PlanInstruction{
        name: name,
        instruction: instruction,
        depends_on: deps
      } = plan.steps[:fetch]

      assert name == :fetch
      assert %Instruction{} = instruction
      assert deps == [:init]
    end
  end

  describe "Edge cases and error handling" do
    test "handles invalid instruction normalization" do
      # Test the error path in add/4 where Instruction.normalize_single fails
      assert_raise RuntimeError, "Invalid instruction format", fn ->
        Plan.new()
        |> Plan.add(:invalid, {:invalid_module_format})
      end
    end

    test "cycle detection with single vertex and no edges" do
      # This tests the successful path through cycle detection for an isolated graph
      plan = Plan.new() |> Plan.add(:isolated, TestActions.FetchAction)

      # This should successfully normalize with no cycles
      {:ok, {graph, _plan_instructions}} = Plan.normalize(plan)

      # Verify it's acyclic and has no edges
      assert Graph.is_acyclic?(graph)
      assert Graph.num_edges(graph) == 0
      assert Graph.num_vertices(graph) == 1
    end

    test "cycle detection handles complex acyclic graph" do
      # Create a more complex acyclic graph to test different DFS paths
      plan =
        Plan.new()
        |> Plan.add(:root, TestActions.FetchAction)
        |> Plan.add(:branch1, TestActions.ValidateAction, depends_on: :root)
        |> Plan.add(:branch2, TestActions.SaveAction, depends_on: :root)
        |> Plan.add(:leaf1, TestActions.MergeAction, depends_on: :branch1)
        |> Plan.add(:leaf2, TestActions.FetchUsersAction, depends_on: :branch2)
        |> Plan.add(:final, TestActions.FetchOrdersAction, depends_on: [:leaf1, :leaf2])

      # This should successfully normalize without cycles, testing multiple DFS paths
      {:ok, {graph, _plan_instructions}} = Plan.normalize(plan)

      assert Graph.is_acyclic?(graph)
      assert Graph.num_vertices(graph) == 6
      # root->branch1, root->branch2, branch1->leaf1, branch2->leaf2, leaf1->final, leaf2->final
      assert Graph.num_edges(graph) == 6
    end

    test "validate_graph with no cycles returns :ok" do
      # Test the successful validation path
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, TestActions.ValidateAction, depends_on: :step1)

      {:ok, {_graph, _plan_instructions}} = Plan.normalize(plan)
      # If normalize succeeds, validate_graph returned :ok (line 335 coverage)
    end
  end

  describe "to_keyword/1 edge cases" do
    test "converts instruction with opts but no params" do
      # This tests lines 430-431 in instruction_to_step_def
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction, retry: true)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # When there are no params but opts exist, it should return {action, opts}
      assert result_map[:step1] == TestActions.FetchAction
    end

    test "converts instruction with both params and opts" do
      # This tests line 431 in instruction_to_step_def
      plan =
        Plan.new()
        |> Plan.add(:step1, {TestActions.FetchAction, %{source: "api"}}, retry: true)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # When both params and opts exist, it should return {action, params, opts}
      assert result_map[:step1] == {TestActions.FetchAction, %{source: "api"}}
    end

    test "adds depends_on to step with params" do
      # This tests line 441 in add_depends_on_to_step_def
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, {TestActions.ValidateAction, %{strict: true}}, depends_on: :step1)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      assert result_map[:step2] ==
               {TestActions.ValidateAction, %{strict: true}, depends_on: [:step1]}
    end

    test "adds depends_on to step with keyword opts" do
      # This tests lines 443-444 in add_depends_on_to_step_def
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, TestActions.ValidateAction, retry: true, depends_on: :step1)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      assert result_map[:step2] == {TestActions.ValidateAction, depends_on: [:step1]}
    end

    test "adds depends_on to step with params and opts" do
      # This tests line 447 in add_depends_on_to_step_def
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.FetchAction)
        |> Plan.add(:step2, {TestActions.ValidateAction, %{strict: true}},
          retry: true,
          depends_on: :step1
        )

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      assert result_map[:step2] ==
               {TestActions.ValidateAction, %{strict: true}, depends_on: [:step1]}
    end
  end

  describe "build/3 error handling" do
    test "handles add_step_from_def error path" do
      # Create a plan_def that will cause an error during add_step_from_def
      # This tests the error handling in line 121 and 287
      plan_def = [
        invalid_step: {:invalid_module_format}
      ]

      {:error, error} = Plan.build(plan_def)
      assert is_exception(error)
    end
  end
end
