# defmodule JidoTest.ExampleAgents.AliceTest do
#   use ExUnit.Case, async: true

#   alias Jido.ExampleAgents.Alice
#   alias Jido.HTN
#   alias Jido.Agent.PlanFrame

#   describe "Alice agent" do
#     setup do
#       alice = Alice.new("alice_1")
#       {:ok, alice: alice}
#     end

#     test "creates a new Alice agent with default values", %{alice: alice} do
#       assert alice.id == "alice_1"
#       assert alice.cycle_count == 0
#     end

#     test "creates a new Alice agent with custom ID" do
#       custom_alice = Alice.new("custom_alice")
#       assert custom_alice.id == "custom_alice"
#       assert custom_alice.cycle_count == 0
#     end

#     test "validates a valid Alice agent", %{alice: alice} do
#       assert {:ok, validated_alice} = Alice.validate(alice)
#       assert validated_alice == alice
#     end

#     test "invalidates an Alice agent with invalid cycle_count" do
#       invalid_alice = %Alice{id: "alice_2", cycle_count: "not_an_integer"}
#       assert {:error, error_message} = Alice.validate(invalid_alice)
#       assert error_message =~ "invalid value for :cycle_count option: expected integer"
#     end

#     test "invalidates an Alice agent with nil id" do
#       invalid_alice = %Alice{id: nil, cycle_count: 0}
#       assert {:error, error_message} = Alice.validate(invalid_alice)
#       assert error_message =~ "invalid value for :id option: expected string, got: nil"
#     end

#     test "sets attributes on Alice agent", %{alice: alice} do
#       updated_alice = Alice.set(alice, %{cycle_count: 5})
#       assert updated_alice.cycle_count == 5
#       assert updated_alice.id == alice.id
#     end

#     test "generates a plan for Alice starting with odd cycle count", %{alice: alice} do
#       result =
#         alice
#         |> Alice.set(%{cycle_count: 1})
#         |> Alice.plan()

#       assert %PlanFrame{} = result
#       assert result.bot.cycle_count == 1
#       assert is_list(result.plan)
#       assert length(result.plan) == 27

#       expected_plan = [
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []}
#       ]

#       assert result.plan == expected_plan
#     end

#     test "generates a plan for Alice starting with even cycle count", %{alice: alice} do
#       result = alice |> Alice.set(%{cycle_count: 0}) |> Alice.plan()

#       assert %PlanFrame{} = result
#       assert result.bot.cycle_count == 0
#       assert is_list(result.plan)
#       assert length(result.plan) == 30

#       expected_plan = [
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is even"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []},
#         {Jido.Actions.Basic.Log, [message: "Cycle count is odd"]},
#         {Jido.Actions.Basic.Sleep, [{:duration_ms, 10}]},
#         {Jido.Actions.Basic.IncrementCycle, []}
#       ]

#       assert result.plan == expected_plan
#     end

#     test "generates a plan for Alice with cycle count at termination threshold", %{alice: alice} do
#       result = alice |> Alice.set(%{cycle_count: 10}) |> Alice.plan()

#       assert %PlanFrame{} = result
#       assert result.bot.cycle_count == 10
#       assert is_list(result.plan)
#       assert Enum.empty?(result.plan)
#     end

#     test "Alice's domain is a valid HTN domain" do
#       domain = Alice.domain()
#       assert %HTN.Domain{} = domain
#       assert domain.name == "Alice"
#       assert Map.has_key?(domain.tasks, "root")
#       assert Map.has_key?(domain.tasks, "cycle")
#       assert Map.has_key?(domain.tasks, "sleep")
#       assert Map.has_key?(domain.tasks, "log_even")
#       assert Map.has_key?(domain.tasks, "log_odd")
#     end

#     test "cycle_count_even? predicate works correctly" do
#       assert Alice.cycle_count_even?(%Alice{id: "alice_3", cycle_count: 0})
#       assert Alice.cycle_count_even?(%Alice{id: "alice_4", cycle_count: 2})
#       refute Alice.cycle_count_even?(%Alice{id: "alice_5", cycle_count: 1})
#       refute Alice.cycle_count_even?(%Alice{id: "alice_6", cycle_count: 3})
#     end

#     test "cycle_count_odd? predicate works correctly" do
#       assert Alice.cycle_count_odd?(%Alice{id: "alice_7", cycle_count: 1})
#       assert Alice.cycle_count_odd?(%Alice{id: "alice_8", cycle_count: 3})
#       refute Alice.cycle_count_odd?(%Alice{id: "alice_9", cycle_count: 0})
#       refute Alice.cycle_count_odd?(%Alice{id: "alice_10", cycle_count: 2})
#     end

#     test "can_continue_cycle? predicate works correctly" do
#       assert Alice.can_continue_cycle?(%Alice{id: "alice_11", cycle_count: 0})
#       assert Alice.can_continue_cycle?(%Alice{id: "alice_12", cycle_count: 9})
#       refute Alice.can_continue_cycle?(%Alice{id: "alice_13", cycle_count: 10})
#       refute Alice.can_continue_cycle?(%Alice{id: "alice_14", cycle_count: 11})
#     end

#     test "should_terminate_cycle? predicate works correctly" do
#       assert Alice.should_terminate_cycle?(%Alice{id: "alice_15", cycle_count: 10})
#       assert Alice.should_terminate_cycle?(%Alice{id: "alice_16", cycle_count: 11})
#       refute Alice.should_terminate_cycle?(%Alice{id: "alice_17", cycle_count: 9})
#       refute Alice.should_terminate_cycle?(%Alice{id: "alice_18", cycle_count: 0})
#     end

#     test "increment_cycle_count transformer works correctly", %{alice: alice} do
#       incremented_alice = Alice.increment_cycle_count(alice)
#       assert incremented_alice.cycle_count == alice.cycle_count + 1
#     end

#     # test "debug_plan returns a PlanFrame with debug_tree", %{alice: alice} do
#     #   result = Alice.debug_plan(alice)
#     #   assert %PlanFrame{} = result
#     #   assert is_binary(result.debug_tree)
#     #   assert String.contains?(result.debug_tree, "root")
#     #   assert String.contains?(result.debug_tree, "cycle")
#     # end

#     test "run executes the plan and returns the final state", %{alice: alice} do
#       plan_frame = Alice.plan(alice)
#       {:ok, final_state} = Alice.run(plan_frame)
#       assert final_state.cycle_count == 10
#     end

#     test "act method executes a full cycle and returns the final state", %{alice: alice} do
#       {:ok, final_state} = Alice.act(alice)
#       assert final_state.cycle_count == 10

#       # Test with custom attributes
#       {:ok, custom_final_state} = Alice.act(alice, %{cycle_count: 5})
#       assert custom_final_state.cycle_count == 10

#       # Test error case
#       {:error, _reason} = Alice.act(%Alice{id: "invalid", cycle_count: -1})
#     end
#   end
# end
